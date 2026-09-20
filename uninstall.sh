#!/usr/bin/env bash
# Remove the iOS-style bar icons: removes your clones of the patched widgets (the bar switches back to the
# built-in ones) and the icon kit. Only removes clones that carry this change (they are your own clones of the stock widgets; if you
# customised one further, that customisation goes with it).
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
widgets=(power network bluetooth audio monitor agents tray weather)
clone_file() { case $1 in tray) echo Tray.qml ;; weather) echo BarWidget.qml ;; *) echo Panel.qml ;; esac; }
command -v omarchy >/dev/null 2>&1 || { echo "needs omarchy on PATH" >&2; exit 1; }

removed=(); kept=()
for w in "${widgets[@]}"; do
  for d in "$plugins"/*."$w"; do
    if [ ! -d "$d" ] || [ ! -f "$d/manifest.json" ]; then continue; fi
    id=$(basename "$d")
    marker=IosIcon; [ "$w" = power ] && marker=iphoneFill
    if grep -q "$marker" "$d/$(clone_file "$w")" 2>/dev/null; then
      if omarchy plugin remove "$id" --yes >/dev/null 2>&1; then echo "removed $id"; removed+=("$id")
      else echo "could not remove $id; remove it with: omarchy plugin remove $id" >&2; kept+=("$id"); fi
    else
      echo "kept $id (does not carry the iOS change; remove it yourself if you want)"; kept+=("$id")
    fi
  done
done
[ -d "$plugins/ioskit" ] && rm -rf "$plugins/ioskit" && echo "removed old shared icon folder"
omarchy restart shell >/dev/null 2>&1 || echo "run: omarchy restart shell" >&2
echo "removed: ${removed[*]:-none}"
[ "${#kept[@]}" -eq 0 ] || echo "kept: ${kept[*]}"
