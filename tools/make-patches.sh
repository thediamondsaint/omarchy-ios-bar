#!/usr/bin/env bash
# Regenerate patches/*.patch from tools/apply-widget.py against a stock Omarchy tree.
#
#   tools/make-patches.sh                 # against the Omarchy installed here
#   tools/make-patches.sh /path/to/omarchy-4.0.4
#
# The patches are only a fast path: the installer applies them when your widget file matches the
# Omarchy they were written against, and runs apply-widget.py when it does not. Keeping them
# generated means the two paths can never drift apart.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root="${1:-${OMARCHY_PATH:-/usr/share/omarchy}}"
stock="$root/shell/plugins"
[ -d "$stock" ] || { echo "no Omarchy shell plugins under $stock" >&2; exit 1; }

widgets=(power network bluetooth audio monitor agents tray weather)
stock_file() {
  case $1 in
    power|network|bluetooth|audio|monitor) echo "panels/$1/Panel.qml" ;;
    agents)  echo "agents/Panel.qml" ;;
    tray)    echo "bar/widgets/Tray.qml" ;;
    weather) echo "panels/weather/BarWidget.qml" ;;
  esac
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for w in "${widgets[@]}"; do
  src="$stock/$(stock_file "$w")"
  name=$(basename "$src")
  mkdir -p "$tmp/a" "$tmp/b"
  # Model.js and friends have to sit next to the copy: apply-widget.py checks them.
  cp "$(dirname "$src")"/*.js "$tmp/b/" 2>/dev/null || true
  cp "$src" "$tmp/a/$name"
  cp "$src" "$tmp/b/$name"
  python3 "$here/tools/apply-widget.py" "$w" "$tmp/b/$name" >/dev/null
  # diff exits 1 because the files differ, which is the point.
  (cd "$tmp" && diff -u "a/$name" "b/$name" || true) \
    | sed -e "1s|^--- a/.*|--- a/$name|" -e "2s|^+++ b/.*|+++ b/$name|" > "$here/patches/$w.patch"
  rm -rf "$tmp/a" "$tmp/b"
  echo "patches/$w.patch  ($(grep -c '^+' "$here/patches/$w.patch") added lines, from $src)"
done
echo "Omarchy used: $(omarchy version 2>/dev/null || echo "$root")"
