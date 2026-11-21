# Crash reports and player feedback (issue #146)

How the game records problems, how players send reports, where reports land, and how Claude turns
them into GitHub issues. What players are told is in [PRIVACY.md](PRIVACY.md).

## In the game

| Piece | Where | What it does |
|---|---|---|
| Session log | `scripts/diag.gd` (autoload `Diag`) | `user://logs/session.log`: game version, build, OS, CPU, GPU, renderer, screen, then a timestamped line whenever the scene, mission or save slot changes. Last 5 sessions kept (`session.1.log` = the one before). |
| Engine log | Godot | Desktop only: `user://logs/godot.log` (plus `godot<date>.log` for earlier sessions) holds every error and warning. Diag prints its breadcrumbs there too (`[last-ink] ...`), so each error sits between "where the player was" lines. The web build has no engine log, so Diag copies the browser console's errors and warnings into `session.log`. |
| Crash / error notice | `Diag.previous`, `title.gd _offer_report` | Desktop: a session that never reached a clean exit (`session.lock` left behind) is a crash. Any build: errors in the last session's logs (shutdown noise after `[last-ink] exit` ignored) count. The title then offers once: Send report / Open log folder / Not now / Don't ask again (until the next game version). |
| Report form | `scripts/feedback_view.gd` | "Report a bug" on the title and every pause menu. Bug / feedback / idea, free text, optional contact, attach screenshot (of the game under the menu), logs, current save. Send, Save to file (zip), Cancel. Nothing is sent without Send. |
| Report building and sending | `scripts/feedback.gd` (`Feedback`) | Builds the report, zips it, POSTs JSON to `endpoint` in `data/feedback.json`. With no endpoint the form has no Send button and only saves zips. |
| Screenshots | `Diag.take_screenshot` | F12 (action `screenshot`) saves `user://screenshots/last-ink_<time>.png`; the web build downloads it. Steam's own overlay also uses F12; both work. |
| Test shortcut | title > Test shortcuts > Log a test error | Logs an error on purpose, so the next launch shows the report offer. Only in builds with the `test_shortcuts` feature; logging, the offer and the form work the same in release builds. |

## Where reports go

`tools/feedback_worker/worker.js` is a Cloudflare Worker (free plan: 100,000 requests a day, no card
needed). For each report it makes one commit in a **private** GitHub repository,
`reports/<yyyy-mm-dd>/<report id>/` with `report.md`, `report.json` and the attachments, and opens an
issue there titled `[bug] <first line> (LI-XXXXXXXX)` with labels `report`, the kind, and `crash`
when the last session crashed or hit errors. It checks the game key, file names and sizes, limits
each address to a few reports, and never stores the IP address. Tests: `node tools/feedback_worker/test.mjs`.

### One-time setup (about 10 minutes, free)

1. **Private repo.** On GitHub, create `Trabiin/last-ink-reports`, private, with a README (so it has a
   `main` branch).
2. **Token.** GitHub > Settings > Developer settings > Fine-grained tokens > Generate: repository
   access *only* `last-ink-reports`; permissions Contents: read and write, Issues: read and write.
   Expiry: 1 year (put a reminder in the calendar to renew it).
3. **Worker.** Sign up at dash.cloudflare.com (free). Workers & Pages > Create > "Hello World" worker,
   name it `last-ink-reports`, Deploy. Then Edit code, replace everything with
   `tools/feedback_worker/worker.js`, Deploy.
4. **Settings.** In the worker: Settings > Variables and Secrets. Add text variables
   `REPORTS_REPO` = `Trabiin/last-ink-reports` and `GAME_KEY` = the `game_key` in `data/feedback.json`,
   and a secret `GITHUB_TOKEN` = the token. Deploy again.
5. **Check.** Open the worker's URL (`https://last-ink-reports.<you>.workers.dev`) in a browser: it
   should say `{"ok":true,"service":"last-ink reports"}`.
6. **Hook up the game.** Put that URL in `endpoint` in `data/feedback.json` (or give it to Claude),
   and add `last-ink-reports` to the Claude project's repositories so triage can read it.

Optional: `tools/feedback_worker/wrangler.toml` deploys the same worker from the command line
(`npx wrangler deploy`, then `npx wrangler secret put GITHUB_TOKEN`) and adds Cloudflare's free
per-address rate limit.

## Triage routine (Claude)

Run it when Ojon asks, after each playtest round, or on a schedule during playtests.

1. List open issues in `Trabiin/last-ink-reports` with label `report`, oldest first.
2. For each: read `report.md`; open the logs (`session.log`, `godot*.log`) and find the first error
   and the breadcrumbs before it; look at `screenshot.png`; load `save_*.json` in a local run when the
   bug needs the exact game (copy it to `user://save_1.json`, the migrations upgrade it).
3. Same problem already filed in `Trabiin/last-ink`? Add a comment there with the new report number,
   version and system (no contact details, no quotes of the player's words).
4. New problem? Open an issue in `Trabiin/last-ink`: what goes wrong, steps to reproduce, version,
   OS/GPU, the error lines, and `Reports: LI-XXXXXXXX`. Labels as usual (`bug`, `release`, milestone).
   Never copy the contact field, the save or the free text word for word into the public repo.
5. Feedback and ideas: collect them in one comment per playtest round on #126 (or the relevant
   design issue), summarised. Playtest surveys (label `survey`, `round-<id>`) are summed up with
   `tools/playtest_report.py` instead; see docs/PLAYTEST.md "After a round".
6. Comment on the report issue with the public issue link and close it (`completed`), or close as
   `not planned` with a reason. Reports for released fixes, and anything older than 12 months, are
   deleted (folder and issue), as PRIVACY.md promises.
7. A player asking for deletion quotes their report number: delete that folder and issue.
