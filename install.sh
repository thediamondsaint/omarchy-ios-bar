#!/usr/bin/env bash
# Install the iOS-style bar icons into your Omarchy setup.
#
#   ./install.sh            clone the widgets into your own plugin folder, patch them, reload the shell
#   ./install.sh --check    verify the icons fit THIS Omarchy's widgets (changes nothing)
#   ./install.sh --status   show what is already installed
#   ./install.sh --verify   check an install is actually live: files, plugins, and the shell's log
#   ./install.sh --diagnose print an environment report to paste into a bug report
#
# Omarchy's rule: never edit /usr/share/omarchy. Built-in widgets are cloned into
# ~/.config/omarchy/plugins/<username>.<widget> (`omarchy plugin clone`) and edited there.
#
# Each widget is handled on its own: one that does not fit your Omarchy is skipped and the rest are
# still installed. Every icon is first applied as an exact patch (generated against Omarchy 4.0.4);
# if your copy of the widget differs, tools/apply-widget.py makes the same change structurally
# instead. Where the widget lives comes from `omarchy plugin catalog`, so moved files are fine too.
# IosIcon.qml is copied into each patched widget's own folder: no shared path to go missing.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
tested="4.0.4"
widgets=(power network bluetooth audio monitor agents tray weather)
# Widgets whose icon is drawn from the widget's own state rather than the shared kit.
kitless=" power "

warn() { printf 'warning: %s\n' "$*" >&2; }
die()  { printf '%s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

for tool in patch jq omarchy; do
  have "$tool" || die "missing required tool: $tool"
done
have python3 || warn "python3 is not installed: widgets that need the adaptive patcher will be skipped"

omarchy_version() { omarchy version 2>/dev/null | head -1; }

# ---- where things are -------------------------------------------------------
# Ask Omarchy itself where each built-in widget lives, so this keeps working when files move.
catalog=""
load_catalog() { [ -n "$catalog" ] || catalog=$(omarchy plugin catalog 2>/dev/null); }

fallback_stock() {   # the 4.0.x layout, used only if the catalog cannot answer
  local root="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins"
  case $1 in
    power|network|bluetooth|audio|monitor) echo "$root/panels/$1/Panel.qml" ;;
    agents)  echo "$root/agents/Panel.qml" ;;
    tray)    echo "$root/bar/widgets/Tray.qml" ;;
    weather) echo "$root/panels/weather/BarWidget.qml" ;;
  esac
}

stock_file() {   # widget -> absolute path of the stock widget file, "" if this Omarchy has no such widget
  local f
  load_catalog
  f=$(printf '%s' "$catalog" | jq -r --arg id "omarchy.$1" '.[] | select(.id == $id) | .barWidgetPath // empty' 2>/dev/null | head -1)
  [ -n "$f" ] && [ -f "$f" ] || f=$(fallback_stock "$1")
  [ -f "$f" ] && echo "$f"
}

find_clone() {   # widget -> your clone's folder (the plugin whose clonedFrom is this built-in)
  local id d
  id=$(omarchy plugin list --json 2>/dev/null \
       | jq -r --arg src "omarchy.$1" '.[] | select(.clonedFrom == $src) | .id' 2>/dev/null | head -1)
  if [ -n "$id" ] && [ -d "$plugins/$id" ]; then echo "$plugins/$id"; return 0; fi
  for d in "$plugins"/*."$1"; do            # fallback: the name a clone gets
    [ -d "$d" ] && [ -f "$d/manifest.json" ] && { echo "$d"; return 0; }
  done
  return 1
}

clone_file() {   # clone folder -> the widget file inside it (from its own manifest)
  local f
  f=$(jq -r '.entryPoints.barWidget // empty' "$1/manifest.json" 2>/dev/null)
  [ -n "$f" ] && [ -f "$1/$f" ] && { echo "$1/$f"; return 0; }
  for f in Panel.qml BarWidget.qml Tray.qml; do
    [ -f "$1/$f" ] && { echo "$1/$f"; return 0; }
  done
  return 1
}

plugin_dirs() { find "$plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

# Marker that a widget file already carries our change.
patched_marker() { case " $1 " in *" power "*) echo iphoneFill ;; *) echo IosIcon ;; esac; }
is_patched() { grep -q "$(patched_marker "$1")" "$2" 2>/dev/null; }
needs_kit()  { case "$kitless" in *" $1 "*) return 1 ;; *) return 0 ;; esac; }
# An install from an older version of this repo, where all widgets shared one ioskit folder.
uses_shared_kit() { grep -q 'import "../ioskit"' "$1" 2>/dev/null; }

# ---- applying ---------------------------------------------------------------
# Try to apply widget $1 to file $2. $3 = --dry-run to only test. Prints "exact" or "adaptive" on success.
apply_widget() {
  local w=$1 f=$2 dry=${3:-} mode=()
  [ "$dry" = "--dry-run" ] && mode=(--dry-run)
  # IOS_BAR_ADAPTIVE_ONLY=1 forces the adaptive patcher (used by the tests).
  if [ -z "${IOS_BAR_ADAPTIVE_ONLY:-}" ] && patch -s "${mode[@]}" "$f" < "$here/patches/$w.patch" >/dev/null 2>&1; then
    echo exact; return 0
  fi
  if have python3 && python3 "$here/tools/apply-widget.py" "$w" "$f" "${mode[@]}" >/dev/null 2>&1; then
    echo adaptive; return 0
  fi
  return 1
}

# 0 = fits this Omarchy's widget (prints exact|adaptive), 2 = no such widget here, 1 = does not fit
applies_to_stock() {
  local src t how rc
  src=$(stock_file "$1") || true
  [ -n "$src" ] || return 2
  t=$(mktemp -d) || return 1
  cp "$src" "$t/" || { rm -rf "$t"; return 1; }
  cp "$(dirname "$src")"/*.js "$t/" 2>/dev/null   # Model.js and friends: the patcher checks them
  how=$(apply_widget "$1" "$t/$(basename "$src")" --dry-run); rc=$?
  rm -rf "$t"
  [ $rc -eq 0 ] && echo "$how"
  return $rc
}

# Put IosIcon.qml next to the widget, and drop the import an older install of this repo left behind.
install_kit() {   # $1 = clone dir, $2 = widget file
  cp "$here/ioskit/IosIcon.qml" "$1/IosIcon.qml" || return 1
  sed -i '\|^import "../ioskit"$|d' "$2"
}

qt_shapes() {   # the icons are drawn with QtQuick.Shapes
  local q
  for q in /usr/lib/qt6/qml /usr/lib/qt/qml /usr/lib64/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml; do
    [ -d "$q/QtQuick/Shapes" ] && { echo "$q/QtQuick/Shapes"; return 0; }
  done
  return 1
}

# ---- preflight --------------------------------------------------------------
preflight() {
  local v
  v=$(omarchy_version)
  if ! omarchy plugin catalog >/dev/null 2>&1; then
    case "$v" in
      3.*|2.*|1.*) die "these icons are for the Omarchy 4 bar (Quickshell). This machine runs Omarchy $v, whose bar is Waybar." ;;
      *) die "\`omarchy plugin catalog\` does not work here, so the bar widgets cannot be found (Omarchy $v). These icons need the Omarchy 4 Quickshell bar." ;;
    esac
  fi
  qt_shapes >/dev/null || die "QtQuick.Shapes is missing, and the icons are drawn with it. On Arch it comes with qt6-declarative: sudo pacman -S --needed qt6-declarative"
}

shell_running() { pgrep -u "$(id -u)" -f 'quickshell.*omarchy|omarchy-shell' >/dev/null 2>&1; }

# ---- commands ---------------------------------------------------------------
check() {
  local w how rc bad=0
  echo "Omarchy $(omarchy_version) (icons written against $tested): checking them against this machine's widgets"
  for w in "${widgets[@]}"; do
    how=$(applies_to_stock "$w"); rc=$?
    case $rc in
      0) printf '  ok        %-10s (%s)\n' "$w" "$how" ;;
      2) printf '  MISSING   %-10s (this Omarchy has no %s widget)\n' "$w" "$w"; bad=1 ;;
      *) printf '  NO FIT    %-10s (neither the patch nor the adaptive patcher fits this build; see README > Troubleshooting)\n' "$w"; bad=1 ;;
    esac
  done
  return $bad
}

status() {
  local w d f
  for w in "${widgets[@]}"; do
    if d=$(find_clone "$w") && f=$(clone_file "$d"); then
      if is_patched "$w" "$f"; then
        if uses_shared_kit "$f"; then          # installed by an older version of this repo
          if [ -f "$plugins/ioskit/IosIcon.qml" ]; then
            echo "  installed (old layout with a shared folder; re-run ./install.sh to migrate)  $w  ($d)"
          else
            echo "  BROKEN          $w  ($d): imports ../ioskit but that folder is gone -> the widget will not load; re-run ./install.sh"
          fi
        elif needs_kit "$w" && [ ! -f "$d/IosIcon.qml" ]; then
          echo "  BROKEN          $w  ($d): patched but IosIcon.qml is missing here -> the widget will not load; re-run ./install.sh"
        else
          echo "  installed       $w  ($d)"
        fi
      else
        echo "  cloned, but not patched (or edited since)  $w  ($d)"
      fi
    else
      echo "  not installed   $w"
    fi
  done
}

# Is the clone the bar actually shows? (`omarchy plugin clone` switches the bar over to it.)
plugin_enabled() { omarchy plugin list --json 2>/dev/null | jq -e --arg id "$1" 'any(.[]; .id == $id and .enabled)' >/dev/null 2>&1; }

shell_errors() {   # QML errors the shell logged in the last $1
  have journalctl || return 0
  journalctl --user --since "-$1" --no-pager 2>/dev/null \
    | grep -E "Plugin widget .* failed|IosIcon|ioskit|TypeError|ReferenceError|Cannot load|is not a type|Unable to assign|is not a function" \
    | grep -v "plugin changed" | sed -E 's/^.*omarchy-shell\[[0-9]+\]: *//' | sort -u | head -10
}

verify() {
  local w d f id bad=0 any=0 errs
  echo "Omarchy $(omarchy_version): checking the installed icons"
  for w in "${widgets[@]}"; do
    if ! d=$(find_clone "$w") || ! f=$(clone_file "$d"); then continue; fi
    is_patched "$w" "$f" || continue
    any=1; id=$(basename "$d")
    if uses_shared_kit "$f"; then
      if [ -f "$plugins/ioskit/IosIcon.qml" ]; then
        echo "  old      $w: installed by an older version of this repo (shared ioskit folder); re-run ./install.sh to migrate"
      else
        echo "  BROKEN   $w: $f imports ../ioskit but that folder is gone; re-run ./install.sh"; bad=1
      fi
    elif needs_kit "$w" && [ ! -f "$d/IosIcon.qml" ]; then
      echo "  BROKEN   $w: $d has no IosIcon.qml"; bad=1
    elif ! plugin_enabled "$id"; then
      echo "  INACTIVE $w: $id is not enabled, so the bar still shows the built-in widget (omarchy plugin enable $id)"; bad=1
    else
      echo "  ok       $w  ($id)"
    fi
  done
  [ $any -eq 1 ] || { echo "  nothing installed yet (run ./install.sh)"; return 1; }
  errs=$(shell_errors "10min")
  if [ -n "$errs" ]; then
    echo; echo "the shell logged these in the last 10 minutes (a widget named here did not load):"
    printf '%s\n' "$errs" | sed 's/^/    /'
    bad=1
  fi
  return $bad
}

install() {
  local w d f id out before after rc backup how src attempt
  local installed=() skipped=() failed=()
  local applicable=()

  preflight
  echo "Omarchy $(omarchy_version); icons written against $tested."
  shell_running || warn "the Omarchy shell does not seem to be running; cloning a widget needs it. Run this from inside your Omarchy session."

  for w in "${widgets[@]}"; do
    if applies_to_stock "$w" >/dev/null; then applicable+=("$w")
    elif d=$(find_clone "$w") && f=$(clone_file "$d") && is_patched "$w" "$f"; then
      applicable+=("$w")        # already installed earlier; leave it be
    else
      skipped+=("$w"); warn "skipping $w: the icon does not fit this Omarchy's widget (run ./install.sh --check)"
    fi
  done
  if [ "${#applicable[@]}" -eq 0 ]; then
    die "None of the icons fit this Omarchy version, nothing was changed."
  fi

  mkdir -p "$plugins"
  backup="$HOME/.config/omarchy/shell.json.bak.ios-bar.$(date +%s)"
  if [ -f "$HOME/.config/omarchy/shell.json" ] && cp "$HOME/.config/omarchy/shell.json" "$backup"; then
    echo "backed up shell.json -> $backup"
  fi

  for w in "${applicable[@]}"; do
    if d=$(find_clone "$w"); then
      echo "reusing your existing clone of $w: $d"
    else
      before=$(plugin_dirs)
      # Each clone makes the shell reload; while it is coming back, the next clone's IPC call can fail
      # through no fault of its own, so give it another go before believing it.
      for attempt in 1 2 3; do
        out=$(omarchy plugin clone "omarchy.$w" 2>&1); rc=$?
        [ $rc -eq 0 ] && break
        find_clone "$w" >/dev/null && { rc=0; break; }
        sleep 2
      done
      if [ $rc -ne 0 ]; then
        warn "omarchy plugin clone omarchy.$w failed: $out"; failed+=("$w"); continue
      fi
      after=$(plugin_dirs)
      d=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
      [ -n "$d" ] || d=$(printf '%s\n' "$out" | sed -nE 's/^Cloned .* to ([^ ]+) and.*/\1/p')
      [ -n "$d" ] || d=$(find_clone "$w")
      if [ -z "$d" ] || [ ! -d "$d" ]; then warn "cloned $w but could not find where it went: $out"; failed+=("$w"); continue; fi
      echo "cloned omarchy.$w -> $d"
    fi

    if ! f=$(clone_file "$d"); then warn "no widget file inside $d, skipping $w"; failed+=("$w"); continue; fi
    if is_patched "$w" "$f"; then
      echo "  already patched: $w"
    elif how=$(apply_widget "$w" "$f"); then
      echo "  patched $(basename "$f") ($how)"
    else
      warn "your clone of $w ($d) differs too much for the patch or the adaptive patcher; leaving it alone"
      skipped+=("$w"); continue
    fi
    if needs_kit "$w"; then
      if install_kit "$d" "$f"; then echo "  icon file -> $d/IosIcon.qml"
      else warn "could not copy IosIcon.qml into $d"; failed+=("$w"); continue; fi
    fi
    id=$(basename "$d")
    plugin_enabled "$id" || omarchy plugin enable "$id" >/dev/null 2>&1 || \
      warn "$id is not enabled; the bar will keep showing the built-in $w (omarchy plugin enable $id)"
    omarchy plugin validate "$d" >/dev/null 2>&1 || warn "omarchy plugin validate reports a problem in $d"
    installed+=("$w")
  done

  if [ "${#installed[@]}" -gt 0 ]; then
    echo "restarting the shell (plugin QML is cached)..."
    omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell; run: omarchy restart shell"
    sleep 5
    out=$(shell_errors "20s")
    [ -n "$out" ] && warn "the shell logged errors after the restart (a widget listed here did not load):"$'\n'"$out"
  fi

  # an older layout of this repo kept one shared folder; remove it once nothing imports it any more
  if [ -d "$plugins/ioskit" ] && ! grep -rqs 'import "../ioskit"' "$plugins"/*/ 2>/dev/null; then rm -rf "$plugins/ioskit"; fi

  echo
  echo "installed: ${installed[*]:-none}"
  [ "${#skipped[@]}" -gt 0 ] && echo "skipped (does not fit / customised): ${skipped[*]}"
  [ "${#failed[@]}"  -gt 0 ] && echo "failed: ${failed[*]}"
  echo "Check it with ./install.sh --verify, undo it with ./uninstall.sh"
  [ "${#installed[@]}" -gt 0 ]
}

diagnose() {
  local w d q
  tilde() { sed "s#$HOME#~#g"; }
  echo "== environment"
  echo "omarchy:         $(omarchy_version)"
  echo "quickshell:      $(quickshell --version 2>/dev/null | head -1)"
  echo "qt6-declarative: $(pacman -Q qt6-declarative 2>/dev/null || echo unknown)"
  echo "QtQuick.Shapes:  $(qt_shapes || echo 'NOT FOUND (the icons need it; on Arch it comes with qt6-declarative)')"
  echo "shell running:   $(shell_running && echo yes || echo no)"
  echo "session:         ${XDG_SESSION_TYPE:-?}   repo: $(git -C "$here" log --format=%h -1 2>/dev/null || echo unknown)"
  echo "OMARCHY_PATH:    ${OMARCHY_PATH:-(unset)}"
  echo
  echo "== where this Omarchy keeps the widgets"
  for w in "${widgets[@]}"; do printf '%-10s %s\n' "$w" "$(stock_file "$w" | tilde)"; done
  echo
  echo "== do the icons fit this Omarchy?"; check
  echo
  echo "== installed"; status | tilde
  echo
  echo "== verify"; verify | tilde
  echo
  echo "== files"
  for w in "${widgets[@]}"; do
    d=$(find_clone "$w") || continue
    printf '%-10s %s\n' "$w" "$(ls "$d" | tr '\n' ' ')" | tilde
  done
  q=$(find "$plugins" \( -name '*.rej' -o -name '*.orig' \) 2>/dev/null | tilde | tr '\n' ' ')
  echo "leftover patch rejects: ${q:-none}"
  echo
  echo "== bar layout (right + center)"
  if have python3 && [ -f "$HOME/.config/omarchy/shell.json" ]; then
    python3 - <<'PY'
import json, os
d = json.load(open(os.path.expanduser("~/.config/omarchy/shell.json")))
lay = d.get("bar", {}).get("layout", {})
for sec in ("right", "center", "left"):
    print(sec + ":", [e.get("id") for e in lay.get(sec, [])])
PY
  else echo "(no shell.json or python3)"; fi
  echo
  echo "== shell errors in the last 10 minutes"
  shell_errors "10min" | tilde | sed 's/^/  /'
  echo "(end of report; paths are shortened to ~, please skim it before sharing)"
}

case "${1:-}" in
  --diagnose) diagnose ;;
  --check)    check ;;
  --status)   status ;;
  --verify)   verify ;;
  ""|--install) install ;;
  *) echo "usage: $0 [--check|--status|--verify|--diagnose]"; exit 2 ;;
esac
