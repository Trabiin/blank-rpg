#!/usr/bin/env python3
"""Playtest round summary (issues #148, #168; docs/PLAYTEST.md).

Reads the survey answers testers sent from the game (kind "survey" reports) and writes the round
summary as Markdown: the numbers per question, the free-text answers grouped by question, and the
AI checks against the targets in data/playtest.json:

  - unprompted AI mentions: testers who bring up AI on the neutral pages, before the survey names it
    (target: under 10%), with the exact words, so the assets or lines they name can be checked;
  - "I wouldn't buy it because of this" on the AI page (target: near the ~8% baseline).

Input is any folder holding reports: a clone of the private reports repo (reports/<day>/<id>/
report.json + survey.json), unzipped report folders, or the .zip files the game saves when it
can't send. Standard library only.

  python3 tools/playtest_report.py ~/last-ink-reports --round r1 > round1.md
  python3 tools/playtest_report.py downloads/ --round r1 --out docs/playtest/r1.md

The summary quotes testers' words. It is for the private reports repo or Ojon, not the public repo:
docs/PLAYTEST.md says what may be copied into public issues.
"""
import argparse
import json
import re
import statistics
import sys
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SURVEY = ROOT / "data" / "survey.json"
SETTINGS = ROOT / "data" / "playtest.json"

# Words that mean a tester is talking about AI. Hits are shown with their sentence so the person
# writing the summary can strike false ones ("randomly generated loot") before reporting the rate.
AI_WORDS = re.compile(
    r"\b(a\.i\.?|ai|gen[- ]?ai|ai[- ](?:generated|art|made|written|slop)|generated|generative|midjourney|"
    r"stable ?diffusion|dall[- ]?e|chat ?gpt|gpt|llm|slop|machine[- ](?:made|written)|neural|"
    r"pixellab|openai|soulless)\b",
    re.IGNORECASE,
)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def find_reports(folder):
    """Yields (report, survey payload, where) for every survey report under folder."""
    folder = Path(folder)
    for rj in sorted(folder.rglob("report.json")):
        try:
            report = load_json(rj)
        except (OSError, ValueError):
            continue
        if report.get("kind") != "survey":
            continue
        sj = rj.parent / "survey.json"
        if not sj.exists():
            continue
        try:
            yield report, load_json(sj), str(rj.parent)
        except (OSError, ValueError):
            continue
    for zp in sorted(folder.rglob("*.zip")):
        try:
            with zipfile.ZipFile(zp) as z:
                names = z.namelist()
                if "report.json" not in names or "survey.json" not in names:
                    continue
                report = json.loads(z.read("report.json").decode("utf-8"))
                if report.get("kind") != "survey":
                    continue
                yield report, json.loads(z.read("survey.json").decode("utf-8")), str(zp)
        except (OSError, ValueError, zipfile.BadZipFile):
            continue


def collect(folder, round_id):
    """Survey responses for one round, one per report id (a report found twice counts once)."""
    seen = set()
    out = []
    for report, payload, where in find_reports(folder):
        rid = report.get("id", where)
        if rid in seen:
            continue
        if round_id and str(payload.get("round", "")).lower() != round_id.lower():
            continue
        seen.add(rid)
        out.append({"id": rid, "report": report, "survey": payload, "answers": payload.get("answers", {}), "where": where})
    out.sort(key=lambda r: str(r["report"].get("created", "")))
    return out


def pct(n, d):
    return "n/a" if d == 0 else f"{100.0 * n / d:.0f}%"


def text_of(q, value):
    if q["type"] == "character":
        if not isinstance(value, dict):
            return ""
        if value.get("id") == "_other":
            return "Someone else: " + str(value.get("other", "")).strip()
        return str(value.get("name") or value.get("id", ""))
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value).strip()


def neutral_pages(survey):
    out = []
    for p in survey["pages"]:
        if p.get("ai"):
            break
        out.append(p)
    return out


def ai_mentions(survey, response):
    """[(question id, snippet)] for AI words in the tester's answers on the neutral pages."""
    hits = []
    for p in neutral_pages(survey):
        for q in p["questions"]:
            v = response["answers"].get(q["id"])
            if v is None:
                continue
            text = text_of(q, v)
            for m in AI_WORDS.finditer(text):
                lo = max(0, text.rfind(".", 0, m.start()) + 1)
                hi = text.find(".", m.end())
                hits.append((q["id"], text[lo: hi + 1 if hi >= 0 else len(text)].strip()))
                break
    return hits


def scale_block(q, responses):
    labels = q.get("labels", [])
    vals = [int(r["answers"][q["id"]]) for r in responses if isinstance(r["answers"].get(q["id"]), (int, float))]
    lines = [f"**{q['prompt']}** ({len(vals)} answered" + (f", average {statistics.mean(vals):.1f} of {len(labels)})" if vals else ")")]
    c = Counter(vals)
    for i, label in enumerate(labels, 1):
        lines.append(f"- {label}: {c.get(i, 0)} ({pct(c.get(i, 0), len(vals))})")
    return lines


def choice_block(q, responses):
    vals = []
    for r in responses:
        v = r["answers"].get(q["id"])
        if v is None:
            continue
        vals.extend(v if isinstance(v, list) else [v])
    n = sum(1 for r in responses if q["id"] in r["answers"])
    lines = [f"**{q['prompt']}** ({n} answered)"]
    c = Counter(text_of(q, v) if q["type"] == "character" else str(v) for v in vals)
    order = q.get("options") or [k for k, _ in c.most_common()]
    for o in order:
        lines.append(f"- {o}: {c.get(o, 0)} ({pct(c.get(o, 0), n)})")
    for o, k in c.most_common():
        if o not in order:
            lines.append(f"- {o}: {k} ({pct(k, n)})")
    return lines


def text_block(q, responses):
    vals = [(r["id"], text_of(q, r["answers"][q["id"]])) for r in responses if q["id"] in r["answers"]]
    lines = [f"**{q['prompt']}** ({len(vals)} answered)"]
    for rid, t in vals:
        lines.append(f"- {t.replace(chr(10), ' / ')} _({rid})_")
    return lines


def summarise(responses, survey, settings, round_id):
    targets = settings.get("targets", {})
    unprompted_max = float(targets.get("unprompted_ai_max", 0.10))
    baseline = float(targets.get("ai_wont_buy_baseline", 0.08))
    alarm = float(targets.get("ai_wont_buy_alarm", 0.12))
    min_n = int(targets.get("min_responses", 10))
    n = len(responses)
    out = [f"# Playtest round {round_id or '(all rounds)'}: survey summary", ""]
    if n == 0:
        out.append("No survey answers found for this round.")
        return "\n".join(out) + "\n"
    first = min(str(r["report"].get("created", "")) for r in responses)
    last = max(str(r["report"].get("created", "")) for r in responses)
    versions = Counter(str(r["report"].get("system", {}).get("game_version", "?")) for r in responses)
    out.append(f"{n} responses, {first[:10]} to {last[:10]}. Game versions: "
               + ", ".join(f"{v} ({k})" for v, k in versions.most_common()) + ".")
    old = [r["id"] for r in responses if int(r["survey"].get("survey_version", 0)) != int(survey.get("version", 0))]
    if old:
        out.append(f"Note: {len(old)} response(s) used a different survey version than data/survey.json "
                   f"(v{survey.get('version')}); their questions may differ: {', '.join(old)}.")
    if n < min_n:
        out.append(f"Note: fewer than {min_n} responses, so the percentages below are rough.")
    out.append("")

    # ---- the AI checks against the targets
    mentions = {r["id"]: ai_mentions(survey, r) for r in responses}
    flagged = [rid for rid, h in mentions.items() if h]
    rate = len(flagged) / n
    reached = [r for r in responses if r["survey"].get("ai_page_seen")]
    wont = [r for r in reached if r["answers"].get("ai_buy") == 1]
    wont_rate = len(wont) / len(reached) if reached else 0.0

    def mark(ok, warn=False):
        return "on target" if ok else ("watch" if warn else "OVER TARGET")

    out += ["## AI checks (issue #168)", "",
            "| Check | Result | Target | |", "|---|---|---|---|",
            f"| Mention AI unprompted (neutral pages) | {len(flagged)} of {n} ({pct(len(flagged), n)}) | under {unprompted_max:.0%} | {mark(rate < unprompted_max)} |",
            f"| \"I wouldn't buy it because of this\" | {len(wont)} of {len(reached)} who reached the AI page ({pct(len(wont), len(reached))}) "
            f"| near {baseline:.0%} (alarm at {alarm:.0%}) | {mark(wont_rate <= baseline, wont_rate <= alarm) if reached else 'n/a'} |",
            "",
            f"{n - len(reached)} tester(s) closed the survey before the AI page.",
            "The unprompted count is automatic (AI words in any neutral answer). Check each quote below and "
            "strike the false ones before reporting the rate.", ""]
    if flagged:
        out.append("**Unprompted AI mentions** (assets go to the artefact audit #166, lines to the script voice pass #167):")
        for rid in flagged:
            for qid, snip in mentions[rid]:
                out.append(f"- `{qid}`: \"{snip}\" _({rid})_")
        out.append("")
    if reached:
        page = next((p for p in survey["pages"] if p.get("ai")), None)
        if page:
            for q in page["questions"]:
                if q["type"] == "scale":
                    out += scale_block(q, reached) + [""]
                elif q["type"] in ("choice", "multi"):
                    out += choice_block(q, reached) + [""]
                else:
                    out += text_block(q, reached) + [""]
    if rate >= unprompted_max or (reached and wont_rate > alarm):
        out += ["**Over target:** the named assets and lines above are the fix list. File them under #166 "
                "(art) and #167 (writing) before the next round.", ""]

    # ---- where people stopped (from the game itself, not the answers)
    play = [float(r["report"].get("context", {}).get("playtime_min", 0) or 0) for r in responses]
    days = [int(r["report"].get("context", {}).get("day", 0) or 0) for r in responses]
    out += ["## Where testers were", "",
            f"Campaign playtime when they answered: median {statistics.median(play):.0f} min "
            f"(shortest {min(play):.0f}, longest {max(play):.0f}). In-game day: median {statistics.median(days):.0f}, furthest {max(days)}.", ""]
    missions = Counter(str(r["report"].get("context", {}).get("mission", "")) or "(not in a mission)" for r in responses)
    out.append("Answered from: " + ", ".join(f"{m} ({k})" for m, k in missions.most_common()) + ".")
    systems = Counter(str(r["report"].get("system", {}).get("os", "?")) for r in responses)
    out.append("Systems: " + ", ".join(f"{s} ({k})" for s, k in systems.most_common()) + ".")
    out.append("")

    # ---- every question, page by page
    for p in survey["pages"]:
        if p.get("ai") or p["id"] == "end":
            continue
        out += [f"## {p['title']}", ""]
        for q in p["questions"]:
            if q["type"] == "scale":
                out += scale_block(q, responses)
            elif q["type"] in ("choice", "multi", "character"):
                out += choice_block(q, responses)
            else:
                out += text_block(q, responses)
            out.append("")
    end = next((p for p in survey["pages"] if p["id"] == "end"), None)
    if end:
        out += ["## Anything else", ""]
        out += text_block(next(q for q in end["questions"] if q["id"] == "anything"), responses)
        contacts = sum(1 for r in responses if str(r["report"].get("contact", "")).strip())
        out += ["", f"{contacts} tester(s) left a way to reach them for the next round (in the reports, not copied here).", ""]

    out += ["## By hand", "",
            "- Recordings and streams watched (#148): who, how long, where they got stuck, and any AI remarks with a timestamp.",
            "- Findings: each one filed as an issue (link) or rejected with a reason.",
            "- Difficulty and pacing notes for #35.", ""]
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("folder", help="folder with the reports (reports repo clone, unzipped reports or .zip files)")
    ap.add_argument("--round", default="", help="round id, e.g. r1 (default: every round)")
    ap.add_argument("--out", default="", help="write the summary here instead of printing it")
    args = ap.parse_args(argv)
    survey = load_json(SURVEY)
    settings = load_json(SETTINGS)
    text = summarise(collect(args.folder, args.round), survey, settings, args.round)
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
