# iOS-style icons for the Omarchy top bar

[![compatibility](https://github.com/thediamondsaint/omarchy-ios-bar/actions/workflows/compatibility.yml/badge.svg)](https://github.com/thediamondsaint/omarchy-ios-bar/actions/workflows/compatibility.yml)

Turns the status icons in the [Omarchy](https://omarchy.org) top bar into one consistent, iPhone-status-bar-style
set: the Wi-Fi fan, a battery with the number in it, a speaker with waves, the bluetooth rune, and matching
weather icons. Everything follows your theme and reacts to real state (signal strength, volume, mute, charging...).

<p align="center"><img src="docs/bar.png" alt="The Omarchy bar: weather icon next to the clock, then chevron, robot, bluetooth, Wi-Fi fan, speaker, display and battery, all drawn in one style"></p>

<p align="center"><img src="docs/icons.png" width="760" alt="Every icon in every state, enlarged and at true bar size"></p>

**What changes**

| Bar item | Now | States |
|---|---|---|
| Battery | rounded outline, nub, fill, number cut into the fill, bolt | charging = theme green, <= 20% = theme red, otherwise foreground |
| Wi-Fi | iOS fan (wedge + two arcs) | 1-3 bars by signal, dimmed bars, slashed when offline, ethernet port |
| Volume | speaker + waves | 0-3 waves by volume, x when muted, headphones for headsets |
| Bluetooth | rune | slashed when off, theme accent when a device is connected |
| Display, agents, tray chevron | display, outlined robot, chevron | agents highlights like the stock widget when alarming |
| Weather | sun, moon, partly cloudy (day/night), cloud, rain, sleet, storm, snow, fog | follows the weather widget's own condition |

The left side (Omarchy logo, workspaces) and the clock are untouched.

## Requirements

- **Omarchy 4** (the Quickshell bar). Checked against every 4.0.x release — 4.0.0, 4.0.1, 4.0.2, 4.0.3, 4.0.4 —
  and against the current development branch; `./install.sh --check` tells you where your own machine stands.
  Omarchy 3 and older use Waybar and are not supported.
- Qt 6.6+ (smooth vector shapes; Omarchy 4 ships Qt 6.11), `patch`, `jq`, `python3`
- Optional, for the measuring tool: `grim`, ImageMagick

Both bar orientations work: the tray chevron turns with a vertical bar, and the battery keeps Omarchy's
own vertical glyph, which fits a side bar better than a lying-down battery would.

## Install

```bash
git clone https://github.com/thediamondsaint/omarchy-ios-bar.git
cd omarchy-ios-bar
./install.sh --check      # read-only: do the patches apply to your Omarchy's stock widgets?
./install.sh              # clone + patch the widgets, add the icon file to each, reload the shell
```

`--check` prints one line per widget, e.g. `ok  network  (exact)` or `ok  network  (adaptive)`. **Exact** means the
patch in `patches/` (generated against Omarchy 4.0.4) applies as is; **adaptive** means your Omarchy build differs
and `tools/apply-widget.py` makes the same change structurally. Each widget is handled on its own: one that fits neither
way is skipped and the rest are still installed. Where your Omarchy keeps each widget comes from `omarchy plugin catalog`,
so a build that moved the files is fine too.

The installer backs up `~/.config/omarchy/shell.json` first (cloning a widget rewrites its entry in the bar layout).
Afterwards:

```bash
./install.sh --verify     # is it actually live? files, enabled plugins, and QML errors from the shell's log
./install.sh --status     # what is installed
./install.sh --diagnose   # full report to paste into a bug report
./uninstall.sh            # undo: removes the clones, the bar goes back to the stock widgets
```

### Tried this before? Start from a clean slate

If an earlier version of this repo, or an install that stopped half-way, left something behind, clear it out
first — a folder a failed `omarchy plugin clone` left is enough to block a fresh clone of that widget
(Omarchy will not clone onto an existing folder, and the installer will tell you which one is in the way).

```bash
cd omarchy-ios-bar          # this repo, freshly pulled: git pull
./uninstall.sh --purge      # removes the icons, then lists every leftover and asks before deleting
./install.sh                # clean install
./install.sh --verify
```

`--purge` clears the clones that carry these icons, folders left by a failed clone, patch leftovers
(`*.rej`, `*.orig`), the shared `ioskit` folder older versions used, and the plugin backups Omarchy keeps
in `~/.config/omarchy/plugins/.<id>.bak.*`. It lists everything before deleting it, leaves plugins that are
not ours alone, and keeps your `shell.json` backups (printing the command to restore one). Add `--yes` to
skip the question.

**Doing it by hand**, if you no longer have the copy of the repo you installed with:

```bash
omarchy plugin list                       # your clones are <username>.<widget>
omarchy plugin remove <username>.network  # repeat for power, bluetooth, audio, monitor, agents, tray, weather
rm -rf ~/.config/omarchy/plugins/ioskit   # only older versions of this repo made this
omarchy restart shell
```

If the bar layout itself looks wrong afterwards, put back a backup the installer made — `ls
~/.config/omarchy/shell.json.bak.ios-bar.*` lists them, and the oldest one is your bar before any of this:

```bash
cp ~/.config/omarchy/shell.json.bak.ios-bar.<oldest> ~/.config/omarchy/shell.json && omarchy restart shell
```

And if you ever edited the stock widgets under `/usr/share/omarchy` directly,
reinstall them with `sudo pacman -S omarchy` — those files are meant to stay untouched.

Never edit files under `/usr/share/omarchy`: Omarchy overwrites them on update. The installer follows Omarchy's own
rule and clones each built-in widget into `~/.config/omarchy/plugins/<username>.<widget>` with `omarchy plugin clone`,
then patches the clone. Your clones survive updates; upstream changes to those widgets just won't reach them.

## How it works

```
ioskit/IosIcon.qml      the icon kit: one component that draws every icon as vector paths. The installer copies it into
                        each patched widget's own folder, so a widget never depends on a shared path
tools/apply-widget.py   the change itself: finds the widget's button by structure and gives it the icon
patches/*.patch         the same change as a plain patch per widget, generated from apply-widget.py (fast path)
tools/make-patches.sh   regenerates patches/ so the two can never drift apart
tests/test-patcher.py   checks both against real Omarchy trees, including edited and broken ones
tools/measure-bar.py    measure icon sizes/alignment from a screenshot
extras/icon-preview/    optional plugin: a window drawing every icon in every state
install.sh, uninstall.sh
```

1. **`BarIconButton` accepts `iconComponent`.** The stock widgets pass a text glyph (`text: root.icon`); a widget can
   instead give it a `Component` to draw. Each patch sets `text: ""` and an `iconComponent` that instantiates `IosIcon`
   with the widget's *existing* state (`root.signalStrength`, `root.outputMuted`, `root.connectedDevices`, ...), so the
   icons stay live. Colours come from the button (`button.foreground`, theme accent), so they follow theme switches.
2. **`IosIcon` draws on a 24x24 grid** with `QtQuick.Shapes` (`PathSvg`, curve renderer). One layer per shape, one stroke
   weight, round caps and joins, dimmed parts at ~30% opacity. Wi-Fi/weather clouds are built from geometry
   (annular sectors, three-lobe clouds from circle intersections) rather than hand-typed coordinates.
3. **Sizes are set by ink, not by box.** A Wi-Fi fan fills less of the grid than a bluetooth rune, so each icon has a
   measured "ink height" and is scaled so every icon is the same visual height; strokes are the same pixel weight
   everywhere. The tables `inkH / inkCx / inkCy` at the top of `IosIcon.qml` hold the calibration.
4. **The battery** is drawn inline in the power widget (it needs the number knocked out of the fill), and its charging
   colour is the theme's own `green`, read from the theme's `colors.toml` and reloaded on theme change.

## Troubleshooting

**Start here:** `./install.sh --verify`. It checks the three things that actually go wrong — the widget file is
patched, `IosIcon.qml` is next to it, and the clone is the plugin the bar is using — and then prints any QML errors
the shell logged. If you open an issue, paste `./install.sh --diagnose`.

- **`NO FIT <widget>` in `--check`.** Neither the exact patch nor the adaptive patcher fits that widget in your Omarchy
  build; it is skipped and everything else still installs. Please open an issue with the output of `./install.sh --diagnose`.
  To do it by hand, follow step 3 of "Make your own" below.
- **A widget (network, audio, ...) disappeared from the bar.** A widget that fails to load vanishes entirely. Run
  `./install.sh --diagnose`: the last section lists `Plugin widget <name> failed: <reason>`. The usual causes are a missing
  `IosIcon.qml` in that widget's folder (re-running `./install.sh` puts it back and also repairs installs from an older
  version of this repo that used a shared folder) or a partially applied hand-made patch (`*.rej`/`*.orig` files are listed).
- **The bar still shows the stock icons although everything installed.** The clone has to be the enabled plugin.
  `--verify` reports this as `INACTIVE <widget>`; fix it with `omarchy plugin enable <user>.<widget>`.
- **`omarchy plugin clone` failed part-way through an install.** Each clone makes the shell reload, and while it is
  restarting its IPC is unavailable, so an operation right after another can fail. Both scripts retry, but if something
  is still missing just run `./install.sh` again — it is safe to re-run and only touches what is not done yet.
- **`... is left over from an earlier attempt and is in the way of a fresh clone`.** A previous attempt left a folder
  where the clone needs to go, and Omarchy will not clone onto an existing folder. `./uninstall.sh --purge` clears it
  (see [Tried this before?](#tried-this-before-start-from-a-clean-slate)), then run `./install.sh` again.
- **An Omarchy update changed a widget.** Your clones keep working (they are copies), they just miss upstream's changes
  to that widget. To take the new version: `omarchy plugin remove <user>.<widget>` and re-run `./install.sh`.
- **Icons look garbled or jagged.** Some graphics drivers mis-draw Qt's curve renderer. In
  `~/.config/omarchy/plugins/<user>.<widget>/IosIcon.qml` set `property bool curveRenderer: false`, then
  `omarchy restart shell`.
- **Nothing changed on the bar.** Plugin QML is cached: `omarchy restart shell`. Then look for QML errors:
  `journalctl --user --since "-2min" --no-pager | grep -iE "typeerror|referenceerror|cannot load|is not a type"`.
- **An icon is missing or looks like an empty gap.** Your Omarchy build probably names a property the widget uses
  differently (for example `signalStrength` in the network widget). It degrades to a dimmed icon rather than crashing;
  edit the `iconComponent` block in your clone (`~/.config/omarchy/plugins/<user>.<widget>/`) to use the right property.
- **Icons are the wrong size or sit too high/low.** Run `tools/measure-bar.py` (see below) and adjust `inkH`/`inkCy` in
  `IosIcon.qml` (in each widget folder; edit the copy in `ioskit/` and re-run `./install.sh` to refresh them all). The nudge and sizes scale with the bar's `iconCanvas`, so a different
  bar font size or display scale usually works, but the calibration was done on a 2x display.
- **Go back to stock.** `./uninstall.sh` (or `omarchy plugin remove <user>.<widget>` for a single widget).

## Keeping it compatible

`tools/apply-widget.py` is the single source of truth: `patches/*.patch` are generated from it
(`tools/make-patches.sh`), so the fast path and the adaptive path always make the same change.

```bash
tests/test-patcher.py                 # against the Omarchy installed here
tests/test-patcher.py ~/omarchy-4.0.0 ~/omarchy-main    # and against any other Omarchy trees
```

For each widget the tests check that the patch applies, that the patcher produces exactly the same file, that the
result is valid QML (`qmlformat`), that every button the widget has is patched (a vertical bar uses its own), that
patching twice is a no-op, that the change survives the kinds of edits an Omarchy update makes to the file
(moved code, extra properties, a reformatted binding, another button above it), and that a widget the icon cannot
honestly fit is refused instead of half-patched.

The icons only read state the widget already has, and they read it defensively: if a future Omarchy renames
`signalStrength` or drops `sink`, the icon falls back to a sensible visible state instead of leaving a blank slot
in your bar.

## Make your own (the method)

This is how the set was built; the same approach works for any bar widget.

1. **Survey.** `omarchy plugin list`, and read how each stock widget picks its icon
   (`grep -n "BarIconButton" -A6 /usr/share/omarchy/shell/plugins/panels/*/Panel.qml`).
2. **Clone, don't edit.** `omarchy plugin clone omarchy.network` -> edit the clone's `Panel.qml`.
3. **Replace the glyph with a drawn icon.** Keep the widget's own state logic; set `text: ""` and
   `iconComponent: Component { IosIcon { kind: "wifi"; level: ...; color: button.foreground } }`.
4. **Reload properly.** Plugin QML is cached: run `omarchy restart shell` after edits, then check
   `journalctl --user --since -20s | grep -iE "typeerror|referenceerror|cannot"` for QML errors.
5. **Preview every state.** You can't unplug the network to see "offline". `extras/icon-preview` (install it with
   `cp -r extras/icon-preview ~/.config/omarchy/plugins/ios-bar.icon-preview && cp ioskit/IosIcon.qml ~/.config/omarchy/plugins/ios-bar.icon-preview/`,
   then `omarchy plugin enable ios-bar.icon-preview`) draws every icon in every state at two sizes; it can save its own PNG (`omarchy-shell shell call ios-bar.icon-preview snapshot /tmp/icons.png`),
   which also avoids capturing the rest of your desktop.
6. **Measure, don't eyeball.** Drawn items are centred geometrically but the bar's text glyphs sit lower in their canvas.
   `tools/measure-bar.py --region "X,Y WxH" --names a,b,c` prints each icon's height and vertical centre from a screenshot;
   adjust `inkH`/`inkCy` until they agree (this repo converged to 25 px tall, centred at 30.5 px, on a 2x display).
   An automated loop (measure -> adjust the tables -> `omarchy restart shell` -> repeat) converges in a few iterations.
7. **Package the change as code, not as a diff.** A diff against one Omarchy version stops applying the moment a
   nearby line changes upstream. Describe the edit structurally (`tools/apply-widget.py`: find the button by its
   `id`, replace its `text:` binding) and generate the patches from it (`tools/make-patches.sh`) — then the fast
   path and the fallback can never disagree, and `tests/test-patcher.py` can check both against other versions.

### Pitfalls worth knowing

- Computing the vertical nudge from font metrics was unreliable (`TextMetrics` has no `ascent`; `FontMetrics` values
  differed between load and render). A NaN in an anchors offset makes the item vanish silently. Calibrate by measurement.
- Only count pixels in the icon colour when measuring; stars in a wallpaper and dimmed bars will skew bounding boxes.
- `grim -g` takes logical pixels and `WxH` with an `x`; on a 2x display the capture is twice as large.
- When previewing, make the window opaque (`tag = "-default-opacity"`, `opacity = "1 1"`), or the desktop shows through.
- Test the real install path, not just `--check`: the first release of this repo passed `--check` everywhere and still
  aborted on the first machine that was not mine.
- Ask Omarchy where its widgets are (`omarchy plugin catalog` has `barWidgetPath`) instead of hard-coding
  `/usr/share/omarchy/shell/plugins/...`; it also answers correctly on a git install.
- A widget can have more than one button: the tray has one for a horizontal bar and one for a vertical bar.

## Tuning

Everything lives in `ioskit/IosIcon.qml` (`inkTarget`, `strokePx`, `dimOpacity`, and the `inkH`/`inkCx`/`inkCy` tables) and,
for the battery, the "iPhone-style battery" block of the power patch (`bodyH`, `bodyW`, `glyphInkDrop`). Edit `ioskit/IosIcon.qml` in this repo
and re-run `./install.sh` (it copies it into every widget), then `omarchy restart shell` if it didn't already.

## License

MIT, see [LICENSE](LICENSE).
