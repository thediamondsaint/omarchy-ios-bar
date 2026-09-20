#!/usr/bin/env bash
# Install the iOS-style bar icons into your Omarchy setup.
#
#   ./install.sh --check    verify the patches apply to THIS Omarchy's stock widgets (changes nothing)
#   ./install.sh --status   show what is already installed
#   ./install.sh            clone the widgets into your own plugin folder, patch them, reload the shell
#
# Omarchy's rule: never edit /usr/share/omarchy. Built-in widgets are cloned into
# ~/.config/omarchy/plugins/<username>.<widget> (`omarchy plugin clone`) and edited there.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
stock="${OMARCHY_PATH:-/usr/share/omarchy}/shell/plugins"
widgets=(power network bluetooth audio monitor agents tray weather)

# widget -> stock file it patches (relative to the stock plugin dir), and the file name inside the clone
stock_file() {
  case $1 in
    power|network|bluetooth|audio|monitor) echo "panels/$1/Panel.qml" ;;
    agents)  echo "agents/Panel.qml" ;;
    tray)    echo "bar/widgets/Tray.qml" ;;
    weather) echo "panels/weather/BarWidget.qml" ;;
  esac
}
clone_file() { basename "$(stock_file "$1")"; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
need patch; need omarchy

find_clone() {  # existing user clone of a widget, if any: ~/.config/omarchy/plugins/<user>.<widget>
  local d
  for d in "$plugins"/*."$1"; do [ -d "$d" ] && [ -f "$d/manifest.json" ] && { echo "$d"; return 0; }; done
  return 1
}

check() {
  local tmp ok=0 w f
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
  echo "Omarchy $(omarchy version 2>/dev/null | head -1): checking patches against stock widgets in $stock"
  for w in "${widgets[@]}"; do
    f="$stock/$(stock_file "$w")"
    if [ ! -f "$f" ]; then echo "  MISSING  $w  ($f)"; ok=1; continue; fi
    cp "$f" "$tmp/$w.qml"
    if patch -s --dry-run "$tmp/$w.qml" < "$here/patches/$w.patch" >/dev/null 2>&1; then
      echo "  ok       $w"
    else
      echo "  CONFLICT $w  (stock file changed since 4.0.4; apply $w.patch by hand)"; ok=1
    fi
  done
  return $ok
}

status() {
  local w d f
  for w in "${widgets[@]}"; do
    if d=$(find_clone "$w"); then
      f="$d/$(clone_file "$w")"
      if patch -s -R --dry-run "$f" < "$here/patches/$w.patch" >/dev/null 2>&1; then
        echo "  installed   $w  ($d)"
      else
        echo "  cloned, not patched (or edited since)  $w  ($d)"
      fi
    else
      echo "  not installed  $w"
    fi
  done
  [ -f "$plugins/ioskit/IosIcon.qml" ] && echo "  icon kit: $plugins/ioskit" || echo "  icon kit: not installed"
}

install() {
  check >/dev/null || { echo "Patches do not all apply to this Omarchy version; run ./install.sh --check" >&2; exit 1; }
  local backup="$HOME/.config/omarchy/shell.json.bak.ios-bar.$(date +%s)"
  cp "$HOME/.config/omarchy/shell.json" "$backup" 2>/dev/null && echo "backed up shell.json -> $backup"

  mkdir -p "$plugins/ioskit"
  cp "$here/ioskit/IosIcon.qml" "$plugins/ioskit/IosIcon.qml"
  echo "installed icon kit -> $plugins/ioskit"

  local w d f out
  for w in "${widgets[@]}"; do
    if d=$(find_clone "$w"); then
      echo "reusing existing clone of $w: $d"
    else
      out=$(omarchy plugin clone "omarchy.$w")
      d=$(printf '%s\n' "$out" | sed -nE 's/^Cloned .* to ([^ ]+) and.*/\1/p')
      [ -d "$d" ] || { echo "could not find the clone of $w in: $out" >&2; exit 1; }
      echo "cloned omarchy.$w -> $d"
    fi
    f="$d/$(clone_file "$w")"
    if patch -s -R --dry-run "$f" < "$here/patches/$w.patch" >/dev/null 2>&1; then
      echo "  already patched: $w"
    else
      patch -s "$f" < "$here/patches/$w.patch"
      echo "  patched $(basename "$f")"
    fi
    omarchy plugin validate "$d"
  done
  echo "restarting the shell (plugin QML is cached)..."
  omarchy restart shell >/dev/null 2>&1 || true
  echo "done. Undo with ./uninstall.sh"
}

case "${1:-}" in
  --check)  check ;;
  --status) status ;;
  ""|--install) install ;;
  *) echo "usage: $0 [--check|--status]"; exit 2 ;;
esac
