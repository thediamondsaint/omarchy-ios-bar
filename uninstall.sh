#!/usr/bin/env bash
# Remove the iOS-style bar icons: removes your clones of the patched widgets (the bar switches back to the
# built-in ones) and the icon kit. Only removes clones that still carry these patches.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugins="$HOME/.config/omarchy/plugins"
widgets=(power network bluetooth audio monitor agents tray weather)
clone_file() { case $1 in tray) echo Tray.qml ;; weather) echo BarWidget.qml ;; *) echo Panel.qml ;; esac; }
for w in "${widgets[@]}"; do
  for d in "$plugins"/*."$w"; do
    [ -d "$d" ] && [ -f "$d/manifest.json" ] || continue
    if patch -s -R --dry-run "$d/$(clone_file "$w")" < "$here/patches/$w.patch" >/dev/null 2>&1; then
      omarchy plugin remove "$(basename "$d")" --yes && echo "removed $(basename "$d")"
    else
      echo "kept $(basename "$d") (not exactly the patched version; remove it yourself if you want)"
    fi
  done
done
rm -rf "$plugins/ioskit" && echo "removed icon kit"
omarchy restart shell >/dev/null 2>&1 || true
