# Desktop builds

Windows, macOS and Linux versions of Last Ink (issue #145). The web build stays the everyday
playtest link; the desktop builds are what itch.io (#126) and Steam (#118, #147) will ship.

## Where to get them

- **Every push to `main` and every pull request:** the
  [Desktop builds](https://github.com/Trabiin/last-ink/actions/workflows/desktop.yml) workflow
  exports all three and uploads them as artifacts (bottom of the run page, needs a GitHub login):
  `LastInk-<version>-windows`, `-macos`, `-linux`. Pull request builds are kept 14 days, `main` 90.
- **Releases:** pushing a tag `v<version>` publishes a
  [GitHub release](https://github.com/Trabiin/last-ink/releases) with the three downloads and a
  changelog made from the merged pull requests. Versions `0.x` are marked pre-release.

| Platform | Download | What is inside |
|---|---|---|
| Windows x86_64 | `LastInk-<v>-windows-x86_64.zip` | `Last Ink/LastInk.exe` (one file, game data embedded), README |
| macOS universal (Intel + Apple Silicon) | `LastInk-<v>-macos.zip` | `Last Ink.app`, ad-hoc signed |
| Linux x86_64 | `LastInk-<v>-linux-x86_64.tar.gz` | `Last Ink/LastInk.x86_64` (one file), icon, `install-desktop-entry.sh` (adds it to the app menu), README |

The README that ships with each download is `tools/desktop/README.txt`.

## Making a release

1. Bump `application/config/version` in `project.godot` (x.y.z) in a pull request and merge it.
   The title screen and every save show this number (`Saves.game_version()`).
2. Tag `main`: `git tag v0.9.1 && git push origin v0.9.1` (or make the release from GitHub's
   Releases page with a new tag).
3. The workflow builds, smoke-tests and publishes. It refuses a tag that does not match the version
   in `project.godot`.

## What CI checks

- **Export presets** (`export_presets.cfg`, checked by `tests/test_display.gd`): Windows, macOS and
  Linux exist, leave out the test shortcuts (#111), tests, tools and docs, have no debug console,
  and take their version from `project.godot`.
- **Windows .exe metadata:** `tools/desktop/check_exe.py` fails the build if the icon or the
  product name and version are still Godot's (rcedit runs on the Windows runner during export).
- **Smoke test on each OS** (`tools/smoke_build.sh`): the exported binary boots headless to the title
  screen, then runs the `scenes`, `saves` and `display` tests from a test pack (the same export with
  `tests/` kept in, made by `tools/smoke_pack.py`) through `--main-pack`. So the shipped engine,
  compiled scripts and imported assets are what gets tested. Any error or warning in the log fails
  it, the same rule as `tools/run_tests.sh`. Windows and macOS run on real Windows and Mac runners.

Run the smoke test locally on Linux (needs the 4.3 Linux export template):

```sh
godot --headless --export-release Linux build/linux/LastInk.x86_64
cp export_presets.cfg /tmp/presets.bak && python3 tools/smoke_pack.py
godot --headless --export-pack Linux build/smoke/linux.pck
cp /tmp/presets.bak export_presets.cfg
tools/smoke_build.sh build/linux/LastInk.x86_64 build/smoke/linux.pck
```

## Saves, settings and logs

`project.godot` gives the game its own folder (`config/use_custom_user_dir`), so `user://` is:

| Platform | Folder |
|---|---|
| Windows | `%APPDATA%\Last Ink` |
| macOS | `~/Library/Application Support/Last Ink` |
| Linux | `~/.local/share/Last Ink` |

Saves (`save_*.json`), options (`settings.cfg`) and Godot's logs (`logs/`) live there. Options >
Save folder opens it. The web build is unaffected (its saves stay in the browser).

## Display options

Options > Display (`scripts/display_settings.gd`, rows in `scripts/options_view.gd`), saved in the
`[display]` section of `settings.cfg`:

- **Window mode:** Windowed, Borderless (borderless fullscreen) or Fullscreen (exclusive).
  **Alt+Enter** or **F11** switch between windowed and the fullscreen kind last used.
- **Window size:** 1280x720 up to 3840x2160, only sizes that fit the screen (windowed only).
- **Scaling:** Smooth (any size) or Pixel-perfect (whole-number scaling only).
- **VSync** on/off and a **frame cap** (off, 30 to 240 fps).
- **In the background:** Pause and mute (default on desktop: fights open their pause menu, the
  Command clock stops), Mute only, or Keep playing (default in the browser).

The browser build shows only Fullscreen, Scaling and In the background. The title screen has Quit on
desktop. `DisplayWatch` (a node on the root, added by `DisplaySettings.apply()`) handles the keys
and the focus changes.

## Icon

`assets/icon/` holds the app icon: a 32x32 pixel drop of ink on paper with the Blank eating the
corner, drawn by `tools/make_icon.py` in the style palette and scaled with nearest-neighbour.
`icon.png` (256) is the project, window, web and Windows icon; `icon_1024.png` becomes the macOS
`.icns`. The presets scale icons with nearest-neighbour too (`application/icon_interpolation=0`).

## Signing (not done; decide later)

Neither build is code-signed. Steam runs unsigned builds fine, so this only matters for downloads
from itch.io or GitHub:

- **macOS:** the app is ad-hoc signed (needed to run on Apple Silicon at all) but not notarised, so
  Gatekeeper asks once (right-click > Open). Signing and notarising needs an Apple Developer account,
  **$99/year**. Godot can then sign and notarise from CI with the account's certificate and an
  app-specific password stored as repository secrets.
- **Windows:** SmartScreen warns about an unsigned .exe from the web until it is downloaded often
  enough. A code-signing certificate is about **$100-300/year**. Likely skip.

Both are tracked as a decision in their own issue (paid, Ojon decides).
