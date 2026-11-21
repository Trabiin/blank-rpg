// Last Ink report inbox (issue #146): a Cloudflare Worker (free plan) that takes the bug reports and
// feedback the game sends (scripts/feedback.gd) and files each one in a PRIVATE GitHub repository:
//   reports/<yyyy-mm-dd>/<report id>/  report.md, report.json and the attachments, in one commit
//   an issue titled "[bug] <first line> (LI-XXXXXXXX)" with labels report + kind, linking to them
// Setup and the triage routine: docs/FEEDBACK.md. What players are told: docs/PRIVACY.md.
//
// Settings (Worker > Settings > Variables and Secrets):
//   GITHUB_TOKEN  secret: fine-grained token for the reports repo only (Contents + Issues: read and write)
//   REPORTS_REPO  e.g. Trabiin/last-ink-reports
//   GAME_KEY      must match "game_key" in data/feedback.json (not a secret, it only keeps random traffic out)
//   RATE_LIMITER  optional Workers rate-limit binding (wrangler.toml); without it a per-instance limit applies
//
// The sender's IP address is used only for the rate limit and never written anywhere.

const MAX_BODY = 4.5 * 1024 * 1024;
const KINDS = ["bug", "feedback", "idea", "survey"]; // survey: playtest answers (issue #168, docs/PLAYTEST.md)
const ID_RE = /^LI-[0-9A-F]{8}$/;
const NAME_RE = /^[A-Za-z0-9_.-]{1,64}$/;
const MAX_FILES = 8;
const PER_HOUR = 6; // reports per IP per hour when there is no rate-limit binding

const recent = new Map(); // ip -> [timestamps], per Worker instance only

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
    if (request.method === "GET") return cors(json({ ok: true, service: "last-ink reports" }));
    if (request.method !== "POST") return cors(json({ ok: false, error: "method" }, 405));
    try {
      return cors(await handle(request, env));
    } catch (e) {
      return cors(json({ ok: false, error: "server" }, 500));
    }
  },
};

async function handle(request, env) {
  const len = Number(request.headers.get("content-length") || 0);
  if (len > MAX_BODY) return json({ ok: false, error: "too big" }, 413);
  const ip = request.headers.get("cf-connecting-ip") || "unknown";
  if (!(await allowed(ip, env))) return json({ ok: false, error: "slow down" }, 429);
  const raw = await request.text();
  if (raw.length > MAX_BODY) return json({ ok: false, error: "too big" }, 413);
  let r;
  try {
    r = JSON.parse(raw);
  } catch (e) {
    return json({ ok: false, error: "bad json" }, 400);
  }
  const problem = validate(r, env);
  if (problem) return json({ ok: false, error: problem }, 400);
  await file(r, env);
  return json({ ok: true, id: r.id });
}

export function validate(r, env) {
  if (!r || typeof r !== "object") return "bad report";
  if (r.game !== "last-ink" || !env.GAME_KEY || r.game_key !== env.GAME_KEY) return "unknown game";
  if (!ID_RE.test(String(r.id))) return "bad id";
  if (!KINDS.includes(r.kind)) return "bad kind";
  if (typeof r.text !== "string" || r.text.length > 4000) return "bad text";
  if (typeof r.contact !== "string" || r.contact.length > 120) return "bad contact";
  const att = r.attachments || {};
  if (typeof att !== "object" || Object.keys(att).length > MAX_FILES) return "too many files";
  for (const [name, a] of Object.entries(att)) {
    if (!NAME_RE.test(name) || name.startsWith(".") || name === "report.md" || name === "report.json") return "bad file name";
    if (!a || (typeof a.data !== "string" && typeof a.base64 !== "string")) return "bad file";
  }
  return "";
}

async function allowed(ip, env) {
  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key: ip });
    return success;
  }
  const now = Date.now();
  const list = (recent.get(ip) || []).filter((t) => now - t < 3600e3);
  if (list.length >= PER_HOUR) return false;
  list.push(now);
  recent.set(ip, list);
  if (recent.size > 5000) recent.clear();
  return true;
}

// ------------------------------------------------------------------ GitHub

async function file(r, env) {
  const repo = env.REPORTS_REPO;
  const day = new Date().toISOString().slice(0, 10);
  const dir = `reports/${day}/${r.id}`;
  const meta = { ...r };
  delete meta.attachments;
  delete meta.game_key;
  const files = [
    { path: `${dir}/report.md`, content: b64(summary(r, dir, repo)) },
    { path: `${dir}/report.json`, content: b64(JSON.stringify(meta, null, 2)) },
  ];
  for (const [name, a] of Object.entries(r.attachments || {})) {
    files.push({ path: `${dir}/${name}`, content: typeof a.base64 === "string" ? a.base64 : b64(a.data) });
  }
  await commit(env, repo, files, `Report ${r.id} (${r.kind})`);
  const first = (r.text || "").split("\n")[0].trim().slice(0, 70) || "(no description)";
  const labels = ["report", r.kind];
  if (r.previous_session && (r.previous_session.crashed || r.previous_session.errors > 0)) labels.push("crash");
  const round = surveyRound(r);
  if (round) labels.push("round-" + round);
  await gh(env, "POST", `/repos/${repo}/issues`, {
    title: `[${r.kind}] ${first} (${r.id})`,
    body: summary(r, dir, repo),
    labels,
  });
}

// The playtest round of a survey report ("r1", "dev", ...), from its survey.json, or "".
export function surveyRound(r) {
  if (r.kind !== "survey") return "";
  const a = (r.attachments || {})["survey.json"];
  try {
    const round = String(JSON.parse(a.data).round || "");
    return /^[a-z0-9-]{1,20}$/i.test(round) ? round.toLowerCase() : "";
  } catch (e) {
    return "";
  }
}

// All files in one commit on the default branch (Git data API), retried once if the branch moved.
async function commit(env, repo, files, message) {
  const info = await gh(env, "GET", `/repos/${repo}`);
  const branch = info.default_branch || "main";
  for (let attempt = 0; attempt < 3; attempt++) {
    const ref = await gh(env, "GET", `/repos/${repo}/git/ref/heads/${branch}`);
    const parent = ref.object.sha;
    const base = await gh(env, "GET", `/repos/${repo}/git/commits/${parent}`);
    const tree = [];
    for (const f of files) {
      const blob = await gh(env, "POST", `/repos/${repo}/git/blobs`, { content: f.content, encoding: "base64" });
      tree.push({ path: f.path, mode: "100644", type: "blob", sha: blob.sha });
    }
    const t = await gh(env, "POST", `/repos/${repo}/git/trees`, { base_tree: base.tree.sha, tree });
    const c = await gh(env, "POST", `/repos/${repo}/git/commits`, { message, tree: t.sha, parents: [parent] });
    const res = await gh(env, "PATCH", `/repos/${repo}/git/refs/heads/${branch}`, { sha: c.sha }, true);
    if (res.ok) return;
    if (res.status !== 422 && res.status !== 409) throw new Error("ref update " + res.status);
  }
  throw new Error("branch kept moving");
}

async function gh(env, method, path, body, raw = false) {
  const res = await fetch("https://api.github.com" + path, {
    method,
    headers: {
      authorization: `Bearer ${env.GITHUB_TOKEN}`,
      accept: "application/vnd.github+json",
      "x-github-api-version": "2022-11-28",
      "user-agent": "last-ink-report-worker",
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (raw) return res;
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status}`);
  return res.json();
}

// ------------------------------------------------------------------ helpers

export function summary(r, dir, repo) {
  const url = (n) => `https://github.com/${repo}/blob/HEAD/${dir}/${n}`;
  const lines = [`**${r.kind}** report \`${r.id}\` from Last Ink ${(r.system || {}).game_version || "?"}, ${r.created || ""}`, ""];
  lines.push(r.text ? quote(r.text) : "_(no description)_", "");
  if (r.contact) lines.push(`Contact: ${r.contact}`, "");
  const p = r.previous_session || {};
  if (p.crashed || p.errors > 0) {
    lines.push(`Previous session: ${p.crashed ? "crashed" : "did not crash"}, ${p.errors || 0} error(s), ${p.warnings || 0} warning(s)`);
    for (const s of p.samples || []) lines.push("    " + String(s));
    lines.push("");
  }
  lines.push("| Where | |", "|---|---|");
  for (const [k, v] of Object.entries(r.context || {})) lines.push(`| ${k} | ${String(v).replace(/\|/g, "/")} |`);
  lines.push("", "| System | |", "|---|---|");
  for (const [k, v] of Object.entries(r.system || {})) lines.push(`| ${k} | ${String(v).replace(/\|/g, "/")} |`);
  const names = Object.keys(r.attachments || {});
  lines.push("", "Files: " + ["report.json", ...names].map((n) => `[${n}](${url(n)})`).join(", "));
  return lines.join("\n");
}

function quote(text) {
  return text.split("\n").map((l) => "> " + l).join("\n");
}

function b64(text) {
  const bytes = new TextEncoder().encode(text);
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json" } });
}

function cors(res) {
  const h = new Headers(res.headers);
  h.set("access-control-allow-origin", "*");
  h.set("access-control-allow-methods", "POST, GET, OPTIONS");
  h.set("access-control-allow-headers", "content-type");
  return new Response(res.body, { status: res.status, headers: h });
}
