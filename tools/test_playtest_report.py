#!/usr/bin/env python3
"""Tests for tools/playtest_report.py (issue #168): python3 tools/test_playtest_report.py"""
import io
import json
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import playtest_report as pr  # noqa: E402


def write_report(folder, rid, answers, round_id="r1", ai_seen=True, kind="survey", zipped=False):
    report = {"id": rid, "kind": kind, "created": "2026-12-01T10:00:00Z", "contact": "",
              "system": {"game_version": "0.9.0", "os": "Windows"},
              "context": {"playtime_min": 80, "day": 6, "mission": ""}}
    survey = {"survey_version": pr.load_json(pr.SURVEY)["version"], "round": round_id, "answers": answers,
              "ai_page_seen": ai_seen}
    if zipped:
        with zipfile.ZipFile(Path(folder) / f"last-ink-report-{rid}.zip", "w") as z:
            z.writestr("report.json", json.dumps(report))
            z.writestr("survey.json", json.dumps(survey))
        return
    d = Path(folder) / "reports" / "2026-12-01" / rid
    d.mkdir(parents=True)
    (d / "report.json").write_text(json.dumps(report))
    (d / "survey.json").write_text(json.dumps(survey))


def main():
    with tempfile.TemporaryDirectory() as tmp:
        write_report(tmp, "LI-00000001", {"enjoy": 4, "odd_art": "Gristle's face looks AI generated in the portrait.",
                                           "ai_buy": 1, "stop_reason": "I got bored"})
        write_report(tmp, "LI-00000002", {"enjoy": 5, "loved": "The fights. The Blank map was great.", "ai_buy": 3,
                                           "alive_most": {"id": "bran", "name": "Bran", "other": ""}})
        write_report(tmp, "LI-00000003", {"enjoy": 2, "ai_text": "AI is fine by me"}, zipped=True)  # AI page only: not unprompted
        write_report(tmp, "LI-00000004", {"enjoy": 1}, ai_seen=False)
        write_report(tmp, "LI-00000005", {"enjoy": 3}, round_id="r2")
        write_report(tmp, "LI-00000006", {"text": "a bug"}, kind="bug")
        write_report(tmp, "LI-00000001", {"enjoy": 4}, zipped=True)  # the same report saved as a zip too: counted once

        responses = pr.collect(tmp, "r1")
        ids = [r["id"] for r in responses]
        assert sorted(ids) == ["LI-00000001", "LI-00000002", "LI-00000003", "LI-00000004"], ids

        survey = pr.load_json(pr.SURVEY)
        hits = pr.ai_mentions(survey, responses[ids.index("LI-00000001")])
        assert hits and hits[0][0] == "odd_art" and "Gristle" in hits[0][1], hits
        assert not pr.ai_mentions(survey, responses[ids.index("LI-00000003")]), "AI page answers are prompted"
        assert not pr.ai_mentions(survey, responses[ids.index("LI-00000002")]), "'Blank map' is not AI"

        text = pr.summarise(responses, survey, pr.load_json(pr.SETTINGS), "r1")
        assert "| Mention AI unprompted (neutral pages) | 1 of 4 (25%) | under 10% | OVER TARGET |" in text, text
        assert "1 of 3 who reached the AI page (33%)" in text, text
        assert "1 tester(s) closed the survey before the AI page." in text
        assert "**Over target:**" in text
        assert "- Bran: 1" in text
        assert "fewer than 10 responses" in text

        out = Path(tmp) / "r1.md"
        assert pr.main([tmp, "--round", "r1", "--out", str(out)]) == 0 and out.read_text().startswith("# Playtest round r1")
        empty = pr.summarise([], survey, {}, "r9")
        assert "No survey answers" in empty
    print("playtest report tests passed")


if __name__ == "__main__":
    main()
