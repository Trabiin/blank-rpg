# Playtest kit (issues #148, #168)

How a playtest round is run, from the build to the summary, with free tools only. The in-game parts
are the welcome note, the **Playtest survey** and **Report a bug**; everything else here is text to
paste and a routine to follow.

Why it is set up this way comes from the AI reception research (project files
`last-ink/research/ai-reception.md`): testers who learn about AI only afterwards feel misled, so the
invite says it up front; and testers' *spontaneous* "this looks AI" remarks are the best guide to
which assets and lines to fix, so the survey asks about art and writing neutrally first and names AI
only at the end.

| Piece | Where |
|---|---|
| Survey questions | `data/survey.json` (pages in order; the page with `"ai": true` is the only one that mentions AI) |
| Playtest settings, targets | `data/playtest.json` (`round`, welcome text, short AI statement fallback, targets) |
| Survey logic | `scripts/survey.gd` (`Survey`): on/off, offers, answers, the report it sends |
| Survey form | `scripts/survey_view.gd` (`SurveyView`), title screen and every pause menu |
| Where answers go | the report inbox (`tools/feedback_worker`, docs/FEEDBACK.md) as kind `survey`, labelled `round-<id>` |
| Round summary | `tools/playtest_report.py` (tests: `python3 tools/test_playtest_report.py`) |
| AI statement | docs/AI_USE.md (issue #164); the game quotes `data/ai_use.json` key `short` |
| Privacy | docs/PRIVACY.md, section "The playtest survey" |

## In the game

- **Which builds.** The survey exists only when `round` in `data/playtest.json` is set (e.g. `"r1"`),
  or in the editor and builds with the `test_shortcuts` feature (as round `dev`, so it can be tried on
  the web link). A release build has an empty `round` and no survey anywhere. A test checks `round` is
  empty or `r<n>`.
- **Welcome note.** The first time a tester reaches the title screen in a round: thanks, "this is
  unfinished", where the survey and bug form are, the screenshot rule, and the short AI statement.
- **Asking for the survey.** On the title screen (including after "Quit to title"), once the tester has
  played `offer_after_min` minutes (30), then again after every 45 more minutes, at most 3 times, with
  "Don't ask again". Never on top of the crash-report offer. A sent survey is never asked for again
  that round; a new round asks afresh. The menu entry stays available all the time.
- **The form.** Six short pages: where you stopped, how it played, look/characters/writing, buying,
  the AI page, thank you. Every answer is optional. Opening the AI page locks the pages before it, so
  nothing said there can be revised after reading about AI; that is what makes an earlier AI remark
  "unprompted". The characters questions offer the tester's own roster plus "Someone else".
- **Sending.** Send on the last page posts the answers through the report inbox. A build without an
  inbox (or a failed send) offers **Save to file** instead (a zip with `survey.json`); the invite tells
  testers where to send that file.
- **What the answers carry.** Answers in English whatever the game's language, the round, the survey
  version, whether the AI page was reached, minutes in the form, and the usual report context (game
  version, OS/GPU, campaign playtime, day, mission). No logs, screenshots or saves.

Changing the questions: only between rounds, and bump `version` in `data/survey.json` so rounds stay
comparable (the summary notes responses from another version). Keep AI out of every page before the
AI page; the test fails otherwise.

## Before a round

1. **Inbox live.** The report worker must be deployed (issue #175, docs/FEEDBACK.md "One-time setup").
   Without it the survey can only save files, and most testers won't send those.
2. **Build.** Set `round` in `data/playtest.json` to the round (`r1`, `r2`, `r3`) in the commit the
   playtest build is made from; set it back to `""` afterwards. Desktop builds come from the desktop
   workflow (issue #145, docs/DESKTOP.md); the web build works too.
3. **itch.io page** (free; issue #126). Make the page *Restricted* with a password or download keys
   for closed rounds, or public for open ones. Fill in itch's AI disclosure honestly (Graphics: yes,
   Text & Dialog: yes, Code: optional, Sound: no) and paste the page section below.
4. **Invite** posted where the testers are (templates below).
5. **Two or three testers who'll record** their first session (see "Recorded sessions").
6. **Ojon checks** the welcome text and AI line in this build (title screen, first launch).

## Text to paste

Use the short AI statement from docs/AI_USE.md word for word everywhere (`<AI short>` below), and link
the full statement (`<AI link>`: https://github.com/Trabiin/last-ink/blob/main/docs/AI_USE.md). The
same wording on itch, in invites and in the game: different versions in different places read as
evasive.

### itch.io page section

> **Playtest (round `<n>`)**
>
> Last Ink is a dark, funny action RPG in the style of the SNES classics: real-time fights with a
> party of three, and a town and territory to run between missions while the Blank eats the map.
> This build covers about `<hours>` hours.
>
> **What we need from you:** play as long as you like, then fill in the survey in the game
> (Menu > Playtest survey, about 5 minutes). It matters most when you stop early: telling us *why*
> is the most useful thing you can do. Bugs: Menu > Report a bug.
>
> **About AI:** `<AI short>` [Read exactly where AI was used](`<AI link>`).
>
> **Please don't share screenshots or videos publicly yet.** Things are unfinished and we'd rather
> people's first look is the real thing. (`<Remove this line for rounds where sharing is OK.>`)
>
> Your answers go to a private place only the developers can read; see the privacy note in the game.

### Community post (r/playmygame, indie RPG Discords and forums)

> **Last Ink, a dark-comedy SNES-style action RPG: looking for playtesters (free, about `<hours>` h)**
>
> Real-time party combat in the Secret of Mana mould, plus a town and territory to run between
> missions while something called the Blank eats the map. Windows, macOS, Linux or in the browser.
>
> I'm after honest first impressions from people who've never seen it. When you stop playing, there's
> a 5-minute survey in the game's menu. Quitting early is useful data too, so please say why.
>
> Upfront about AI: `<AI short>` Details: `<AI link>`
>
> Link: `<itch link>` (password `<password>`). Please keep screenshots to yourself until release.

### Direct invite (friends of friends, testers from earlier rounds)

> Hi `<name>`! I'm running a playtest of Last Ink, an SNES-style action RPG, and would love your honest
> take. It's about `<hours>` hours; play as much as you feel like. When you stop, there's a short
> survey in the menu (Menu > Playtest survey). Knowing where and why you stopped helps most.
>
> One thing to know beforehand: `<AI short>` (`<AI link>`)
>
> `<itch link>`, password `<password>`. Please don't post screenshots or clips yet. Thank you!

### Asking someone to record

> Would you be up for recording your first session? Free tools work fine: OBS Studio on PC, or the
> Xbox Game Bar (Win+G). Please think out loud: what you're trying to do, what you expect, what
> surprises or annoys you. Then send me the file or a private/unlisted link. It's only for me, and
> I'll delete it when the round is done.

## Screenshots and clips

Closed rounds: testers are asked (welcome note, itch page, invite) not to share screenshots or clips
publicly. That keeps unfinished assets from becoming the first public image of the game. When a
round's build is fine to show (e.g. the demo, #147), say so in the invite and drop the line from the
itch page; the welcome note already says "unless the invite says that's OK".

## Recorded sessions

Ask 2-3 testers per round. Watching beats survey answers for confusion, because people don't report
what they didn't notice. Keep a log per video:

| Time | What happened | Kind (stuck / confused / delighted / bug / AI remark) | Issue |
|---|---|---|---|

Note every remark about art or text looking generated, "off", inconsistent or "AI", with a timestamp
and what was on screen. Those count toward the unprompted-AI findings even though they aren't in the
survey. Delete the videos once the round summary is written.

## The survey, question by question

| Page | Asks | Why |
|---|---|---|
| Where you stopped | why they stopped, where, would they keep playing | #148: where people quit and why; the game adds playtime, day and mission itself |
| How it played | enjoyment, difficulty, pace, loved / confused / annoyed | #148 and the balance pass #35 |
| Look, characters and writing | art rating, anything out of place or inconsistent (and where), most and least alive character, writing rating, flat or generic dialogue | #168: neutral questions whose answers point at assets (#166) and lines (#167), and where unprompted AI remarks show up |
| If it were out today | would buy, fair price, similar games, input device, how often they play the genre | #148, the price decision #155 |
| One last question | the AI statement, then: knew before?, feel worse/better?, buy because of it?, free text | #168: the direct question, last |
| Thank you | anything else, contact for the next round | |

## After a round

1. **Triage the inbox** as docs/FEEDBACK.md says (bug reports first; surveys are labelled `survey` and
   `round-<id>`).
2. **Run the summary** on a local clone of the reports repo:
   `python3 tools/playtest_report.py ~/last-ink-reports --round r1 --out ~/last-ink-reports/rounds/r1.md`
   It counts every question, lists the free-text answers per question, and checks the AI targets:
   - **Unprompted AI mentions** on the neutral pages: target **under 10%** of responses. The count is
     automatic (AI words in any neutral answer), so read each quote and strike false hits ("randomly
     generated loot") first. Add AI remarks from the recordings.
   - **"I wouldn't buy it because of this"** on the AI page: target **near 8%** of those who reached
     it (GameDiscoverCo's survey of Steam fans), alarm above 12%.
   Targets live in `data/playtest.json` `targets`.
3. **Act on it.** Every asset named as out of place, inconsistent or AI-looking goes to the artefact
   audit (#166); every line named as flat, generic or AI-sounding goes to the script voice pass (#167).
   Over target means those lists are fixed before the next round. Other findings become issues or are
   rejected with a reason (#148).
4. **Publish the summary on #148** (public): numbers, the targets table, and findings in our own words,
   with links to the issues. Never testers' words verbatim, contact details or report contents beyond a
   description (the same rule as docs/FEEDBACK.md). The full summary with quotes stays in the private
   reports repo.
5. **Reset** `round` to `""` (or the next round) and invite the testers who left contact details.

Write the summary in this shape:

```
## Round r1 (build 0.x, dates): N responses, M recordings

| Check | Result | Target |
|---|---|---|
| Unprompted AI mentions | x of N (y%) | under 10% |
| "Wouldn't buy because of AI" | x of K (y%) | near 8%, alarm 12% |

Where people stopped: ...
Top confusions: ... (issues)
Art / writing named: ... (#166 / #167 items)
Difficulty and pacing: ... (#35)
Would buy / price: ...
Changes for the next build: ...
```
