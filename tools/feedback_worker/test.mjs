// Tests for the report worker with a fake GitHub API: node tools/feedback_worker/test.mjs
import assert from "node:assert/strict";
import worker, { validate } from "./worker.js";

const env = { GITHUB_TOKEN: "t", REPORTS_REPO: "o/reports", GAME_KEY: "k" };
let calls = [];
let refMoves = 0;
globalThis.fetch = async (url, init) => {
  const path = url.replace("https://api.github.com", "");
  const body = init.body ? JSON.parse(init.body) : null;
  calls.push({ method: init.method, path, body });
  assert.equal(init.headers.authorization, "Bearer t");
  const ok = (o) => new Response(JSON.stringify(o), { status: 200 });
  if (path === "/repos/o/reports") return ok({ default_branch: "main" });
  if (path.startsWith("/repos/o/reports/git/ref/")) return ok({ object: { sha: "p1" } });
  if (path.startsWith("/repos/o/reports/git/commits/") && init.method === "GET") return ok({ tree: { sha: "t0" } });
  if (path === "/repos/o/reports/git/blobs") return ok({ sha: "b" + calls.length });
  if (path === "/repos/o/reports/git/trees") return ok({ sha: "t1" });
  if (path === "/repos/o/reports/git/commits") return ok({ sha: "c1" });
  if (path.startsWith("/repos/o/reports/git/refs/")) {
    if (refMoves > 0) { refMoves--; return new Response("{}", { status: 422 }); }
    return ok({});
  }
  if (path === "/repos/o/reports/issues") return ok({ number: 1 });
  throw new Error("unexpected " + init.method + " " + path);
};

const report = (extra = {}) => ({
  id: "LI-0A1B2C3D", game: "last-ink", game_key: "k", kind: "bug", created: "2026-11-21T10:00:00Z",
  text: "Froze in the Forge\nwhen upgrading", contact: "", system: { game_version: "0.9.0", os: "Windows" },
  context: { scene: "res://scenes/hub.tscn", day: 4 }, previous_session: { crashed: true, errors: 2, samples: ["SCRIPT ERROR: x"] },
  attachments: { "session.log": { type: "text/plain", data: "hello ✓" }, "screenshot.png": { type: "image/png", base64: "iVBORw0KGgo=" } },
  ...extra,
});
const post = (body, headers = {}) => worker.fetch(new Request("https://w.example/", {
  method: "POST", body: typeof body === "string" ? body : JSON.stringify(body),
  headers: { "content-type": "application/json", "cf-connecting-ip": headers.ip || "1.1.1.1" },
}), env);

// A good report: one commit with every file, then an issue.
let res = await post(report());
let out = await res.json();
assert.equal(res.status, 200, JSON.stringify(out));
assert.deepEqual(out, { ok: true, id: "LI-0A1B2C3D" });
assert.equal(res.headers.get("access-control-allow-origin"), "*");
const tree = calls.find((c) => c.path === "/repos/o/reports/git/trees").body.tree.map((t) => t.path.split("/").pop());
assert.deepEqual(tree.sort(), ["report.json", "report.md", "screenshot.png", "session.log"]);
const blobs = calls.filter((c) => c.path.endsWith("/git/blobs")).map((c) => c.body.content);
assert.ok(blobs.includes("iVBORw0KGgo="), "base64 attachments pass through");
assert.ok(blobs.includes(Buffer.from("hello ✓").toString("base64")), "text attachments are utf-8");
const meta = JSON.parse(Buffer.from(blobs[1], "base64").toString());
assert.equal(meta.game_key, undefined, "the key is not stored");
assert.equal(meta.attachments, undefined);
const issue = calls.find((c) => c.path === "/repos/o/reports/issues").body;
assert.equal(issue.title, "[bug] Froze in the Forge (LI-0A1B2C3D)");
assert.deepEqual(issue.labels, ["report", "bug", "crash"]);
assert.ok(issue.body.includes("> Froze in the Forge"));
assert.ok(issue.body.includes("https://github.com/o/reports/blob/HEAD/reports/"), "absolute links to the files");
assert.ok(!JSON.stringify(calls).includes("1.1.1.1"), "the IP is never written");

// The branch moved during the commit: retried.
calls = []; refMoves = 1;
res = await post(report(), { ip: "2.2.2.2" });
assert.equal(res.status, 200);
assert.equal(calls.filter((c) => c.path.startsWith("/repos/o/reports/git/refs/")).length, 2);

// Refused: wrong key, bad id, bad names, too much text, bad JSON, wrong method.
for (const [extra, why] of [[{ game_key: "x" }, "unknown game"], [{ id: "../x" }, "bad id"], [{ kind: "rant" }, "bad kind"],
  [{ text: "x".repeat(4001) }, "bad text"], [{ attachments: { "../etc": { data: "" } } }, "bad file name"],
  [{ attachments: { "report.md": { data: "" } } }, "bad file name"]]) {
  calls = [];
  res = await post(report(extra), { ip: "3.3.3." + why.length });
  assert.equal(res.status, 400, why);
  assert.equal((await res.json()).error, why);
  assert.equal(calls.length, 0, "nothing reaches GitHub: " + why);
}
assert.equal((await post("{nope", { ip: "4.4.4.4" })).status, 400);
assert.equal((await worker.fetch(new Request("https://w.example/", { method: "PUT" }), env)).status, 405);
assert.equal((await worker.fetch(new Request("https://w.example/", { method: "OPTIONS" }), env)).status, 204);
assert.equal(validate(report(), { GAME_KEY: "" }), "unknown game", "no key configured: refuse everything");

// Rate limit without a binding: the seventh report in an hour from one address is refused.
let last;
for (let i = 0; i < 7; i++) last = await post(report(), { ip: "9.9.9.9" });
assert.equal(last.status, 429);

console.log("worker tests passed");
