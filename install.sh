#!/usr/bin/env bash
# Install the iOS-style bar icons into your Omarchy setup.
#
#   ./install.sh --check    verify the patches apply to THIS Omarchy's stock widgets (changes nothing)
#   ./install.sh --status   show what is already installed
#   ./install.sh            clone the widgets into your own plugin folder, patch them, reload the shell
#
# Omarchy's rule: never edit /usr/share/omarchy. Built-in widgets are cloned into
# ~/.config/omarchy/plugins/<username>.<widget> (`omarchy plugin clone`) and edited there.
# Each widget is handled independently: one that does not apply to your Omarchy version is skipped,
# the others are still installed. Every icon is first applied as an exact patch (written against Omarchy
# 4.0.4); if the widget differs in your Omarchy build, tools/apply-widget.py applies the same change
# structurally instead (the battery/power widget is exact-patch only).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
stock="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins"
tested="4.0.4"
widgets=(power network bluetooth audio monitor agents tray weather)

stock_file() {   # widget -> the stock file its patch is written against
  case $1 in
    power|network|bluetooth|audio|monitor) echo "panels/$1/Panel.qml" ;;
    agents)  echo "agents/Panel.qml" ;;
    tray)    echo "bar/widgets/Tray.qml" ;;
    weather) echo "panels/weather/BarWidget.qml" ;;
  esac
}
clone_file() { basename "$(stock_file "$1")"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

for tool in patch omarchy; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required tool: $tool" >&2; exit 1; }
done
[ -d "$stock" ] || { echo "Omarchy's stock widgets not found at $stock (set OMARCHY_PATH if Omarchy lives elsewhere)" >&2; exit 1; }

omarchy_version() { omarchy version 2>/dev/null | head -1; }

# Marker that a widget file already carries our change.
patched_marker() { if [ "$1" = power ]; then echo iphoneFill; else echo IosIcon; fi; }
is_patched() { grep -q "$(patched_marker "$1")" "$2" 2>/dev/null; }

# Try to apply widget $1 to file $2. $3 = --dry-run to only test. Prints "exact" or "adaptive" on success.
# Returns 0 if applied/applicable, 1 if not.
apply_widget() {
  local w=$1 f=$2 dry=${3:-} mode=()
  [ "$dry" = "--dry-run" ] && mode=(--dry-run)
  # IOS_BAR_ADAPTIVE_ONLY=1 forces the adaptive patcher (testing); the battery has no adaptive form and stays exact.
  if { [ -z "${IOS_BAR_ADAPTIVE_ONLY:-}" ] || [ "$w" = power ]; } && patch -s "${mode[@]}" "$f" < "$here/patches/$w.patch" >/dev/null 2>&1; then
    echo exact; return 0
  fi
  if [ "$w" != power ] && command -v python3 >/dev/null 2>&1 \
     && python3 "$here/tools/apply-widget.py" "$w" "$f" "${mode[@]}" >/dev/null 2>&1; then
    echo adaptive; return 0
  fi
  return 1
}

# 0 = applicable to this Omarchy's stock widget (prints exact|adaptive), 2 = stock file missing, 1 = conflict
applies_to_stock() {
  local f="$stock/$(stock_file "$1")" t how
  [ -f "$f" ] || return 2
  t=$(mktemp) || return 1
  cp "$f" "$t"
  how=$(apply_widget "$1" "$t" --dry-run); local rc=$?
  rm -f "$t"
  [ $rc -eq 0 ] && echo "$how"
  return $rc
}

find_clone() {   # an existing user clone of a widget: ~/.config/omarchy/plugins/<user>.<widget>
  local d
  for d in "$plugins"/*."$1"; do
    if [ -d "$d" ] && [ -f "$d/manifest.json" ]; then echo "$d"; return 0; fi
  done
  return 1
}
plugin_dirs() { find "$plugins" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

check() {
  local w rc how bad=0
  echo "Omarchy $(omarchy_version) (patches written against $tested): checking them against the stock widgets in $stock"
  for w in "${widgets[@]}"; do
    how=$(applies_to_stock "$w"); rc=$?
    case $rc in
      0) echo "  ok        $w   ($how)" ;;
      2) echo "  MISSING   $w   (this Omarchy has no $(stock_file "$w"))"; bad=1 ;;
      *) echo "  CONFLICT  $w   (neither the exact patch nor the adaptive patcher fits this build; see README > Troubleshooting)"; bad=1 ;;
    esac
  done
  return $bad
}

status() {
  local w d f
  for w in "${widgets[@]}"; do
    if d=$(find_clone "$w"); then
      f="$d/$(clone_file "$w")"
      if is_patched "$w" "$f"; then
        echo "  installed       $w  ($d)"
      else
        echo "  cloned, but not patched (or edited since)  $w  ($d)"
      fi
    else
      echo "  not installed   $w"
    fi
  done
  if [ -f "$plugins/ioskit/IosIcon.qml" ]; then echo "  icon kit:       $plugins/ioskit"; else echo "  icon kit:       not installed"; fi
}

install() {
  local w d f out before after rc backup how
  local installed=() skipped=() failed=()
  local applicable=()

  echo "Omarchy $(omarchy_version); patches written against $tested."
  for w in "${widgets[@]}"; do
    if applies_to_stock "$w" >/dev/null; then applicable+=("$w")
    else
      # the stock file may still be fine if the user already cloned+patched it earlier
      if d=$(find_clone "$w") && is_patched "$w" "$d/$(clone_file "$w")"; then
        applicable+=("$w")
      else
        skipped+=("$w"); warn "skipping $w: no patch fits this Omarchy's stock widget (run ./install.sh --check)"
      fi
    fi
  done
  if [ "${#applicable[@]}" -eq 0 ]; then
    echo "None of the patches apply to this Omarchy version, nothing was changed." >&2; exit 1
  fi

  mkdir -p "$plugins"
  backup="$HOME/.config/omarchy/shell.json.bak.ios-bar.$(date +%s)"
  if [ -f "$HOME/.config/omarchy/shell.json" ] && cp "$HOME/.config/omarchy/shell.json" "$backup"; then
    echo "backed up shell.json -> $backup"
  fi

  mkdir -p "$plugins/ioskit" && cp "$here/ioskit/IosIcon.qml" "$plugins/ioskit/IosIcon.qml" || { echo "could not install the icon kit" >&2; exit 1; }
  echo "installed icon kit -> $plugins/ioskit"

  for w in "${applicable[@]}"; do
    if d=$(find_clone "$w"); then
      echo "reusing your existing clone of $w: $d"
    else
      before=$(plugin_dirs)
      out=$(omarchy plugin clone "omarchy.$w" 2>&1); rc=$?
      if [ $rc -ne 0 ]; then warn "omarchy plugin clone omarchy.$w failed: $out"; failed+=("$w"); continue; fi
      after=$(plugin_dirs)
      d=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -1)
      [ -n "$d" ] || d=$(printf '%s\n' "$out" | sed -nE 's/^Cloned .* to ([^ ]+) and.*/\1/p')
      if [ -z "$d" ] || [ ! -d "$d" ]; then warn "cloned $w but could not find where it went: $out"; failed+=("$w"); continue; fi
      echo "cloned omarchy.$w -> $d"
    fi

    f="$d/$(clone_file "$w")"
    if [ ! -f "$f" ]; then warn "$f not found, skipping $w"; failed+=("$w"); continue; fi
    if is_patched "$w" "$f"; then
      echo "  already patched: $w"; installed+=("$w")
    elif how=$(apply_widget "$w" "$f"); then
      echo "  patched $(basename "$f") ($how)"; installed+=("$w")
    else
      warn "your clone of $w ($d) differs too much for the patch or the adaptive patcher; leaving it alone"
      skipped+=("$w"); continue
    fi
    omarchy plugin validate "$d" >/dev/null 2>&1 || warn "omarchy plugin validate reports a problem in $d"
  done

  if [ "${#installed[@]}" -gt 0 ]; then
    echo "restarting the shell (plugin QML is cached)..."
    omarchy restart shell >/dev/null 2>&1 || warn "could not restart the shell; run: omarchy restart shell"
    sleep 5
    if command -v journalctl >/dev/null 2>&1; then
      out=$(journalctl --user --since "-20s" --no-pager 2>/dev/null \
            | grep -E "IosIcon|ioskit|TypeError|ReferenceError|Cannot load|is not a type|Unable to assign" | grep -v "plugin changed" | head -5)
      [ -n "$out" ] && warn "the shell logged QML errors after the restart:"$'\n'"$out"
    fi
  fi

  echo
  echo "installed: ${installed[*]:-none}"
  [ "${#skipped[@]}" -gt 0 ] && echo "skipped (does not apply / customised): ${skipped[*]}"
  [ "${#failed[@]}"  -gt 0 ] && echo "failed: ${failed[*]}"
  echo "Undo with ./uninstall.sh"
  [ "${#installed[@]}" -gt 0 ]
}

case "${1:-}" in
  --check)  check ;;
  --status) status ;;
  ""|--install) install ;;
  *) echo "usage: $0 [--check|--status]"; exit 2 ;;
esac
