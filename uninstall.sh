#!/usr/bin/env bash
# Remove the iOS-style bar icons: removes your clones of the patched widgets, so the bar goes back to
# Omarchy's built-in ones. Only clones that carry this change are removed (if you customised one of
# them further, that customisation goes with it); anything else is left alone and named.
set -uo pipefail
plugins="$HOME/.config/omarchy/plugins"
widgets=(power network bluetooth audio monitor agents tray weather)
command -v omarchy >/dev/null 2>&1 || { echo "needs omarchy on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "needs jq" >&2; exit 1; }

find_clone() {   # widget -> your clone's folder
  local id d
  id=$(omarchy plugin list --json 2>/dev/null \
       | jq -r --arg src "omarchy.$1" '.[] | select(.clonedFrom == $src) | .id' 2>/dev/null | head -1)
  if [ -n "$id" ] && [ -d "$plugins/$id" ]; then echo "$plugins/$id"; return 0; fi
  for d in "$plugins"/*."$1"; do
    [ -d "$d" ] && [ -f "$d/manifest.json" ] && { echo "$d"; return 0; }
  done
  return 1
}
clone_file() {
  local f
  f=$(jq -r '.entryPoints.barWidget // empty' "$1/manifest.json" 2>/dev/null)
  [ -n "$f" ] && [ -f "$1/$f" ] && { echo "$1/$f"; return 0; }
  for f in Panel.qml BarWidget.qml Tray.qml; do
    [ -f "$1/$f" ] && { echo "$1/$f"; return 0; }
  done
  return 1
}

# Removing a plugin makes the shell reload, and while it is coming back its IPC is not there, so a
# removal right after another can fail through no fault of its own. Try again, then look at the result.
remove_plugin() {   # $1 = plugin id, $2 = its folder
  local attempt
  for attempt in 1 2 3 4; do
    omarchy plugin remove "$1" --yes >/dev/null 2>&1
    [ -d "$2" ] || return 0
    sleep 2
  done
  [ ! -d "$2" ]
}

removed=(); kept=()
for w in "${widgets[@]}"; do
  d=$(find_clone "$w") || continue
  f=$(clone_file "$d") || continue
  id=$(basename "$d")
  marker=IosIcon; [ "$w" = power ] && marker=iphoneFill
  if grep -q "$marker" "$f" 2>/dev/null; then
    if remove_plugin "$id" "$d"; then echo "removed $id"; removed+=("$id")
    else echo "could not remove $id; remove it with: omarchy plugin remove $id" >&2; kept+=("$id"); fi
  else
    echo "kept $id (it does not carry the iOS change; remove it yourself if you want)"; kept+=("$id")
  fi
done
[ -d "$plugins/ioskit" ] && rm -rf "$plugins/ioskit" && echo "removed the old shared icon folder"
omarchy restart shell >/dev/null 2>&1 || echo "run: omarchy restart shell" >&2
echo "removed: ${removed[*]:-none}"
[ "${#kept[@]}" -eq 0 ] || echo "kept: ${kept[*]}"
