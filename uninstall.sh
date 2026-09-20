#!/usr/bin/env bash
# Remove the iOS-style bar icons: removes your clones of the patched widgets, so the bar goes back to
# Omarchy's built-in ones. Only clones that carry this change are removed (if you customised one of
# them further, that customisation goes with it); anything else is left alone and named.
#
#   ./uninstall.sh           remove the icons
#   ./uninstall.sh --purge   also clear out what an earlier, half-finished attempt can leave behind:
#                            folders a failed `omarchy plugin clone` left, patch leftovers (*.rej,
#                            *.orig), the old shared ioskit folder, and the plugin backups Omarchy
#                            keeps. Lists everything before deleting; --yes skips the question.
set -uo pipefail
plugins="$HOME/.config/omarchy/plugins"
config="$HOME/.config/omarchy"
widgets=(power network bluetooth audio monitor agents tray weather)
purge=0; assume_yes=0
for arg in "$@"; do
  case "$arg" in
    --purge) purge=1 ;;
    --yes|-y) assume_yes=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done
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

# ---- --purge: leftovers from an earlier attempt -----------------------------
if [ "$purge" -eq 1 ]; then
  leftovers=()
  # a clone folder a failed `omarchy plugin clone` left behind: it is in the way of a fresh clone,
  # because Omarchy refuses to clone onto an existing folder
  for w in "${widgets[@]}"; do
    for d in "$plugins"/*."$w"; do
      [ -d "$d" ] || continue
      [ -f "$d/manifest.json" ] && continue      # a real plugin: handled above, never deleted here
      leftovers+=("$d")
    done
  done
  # patch leftovers from a hand-made or interrupted patch
  while IFS= read -r p; do [ -n "$p" ] && leftovers+=("$p"); done \
    < <(find "$plugins" \( -name '*.rej' -o -name '*.orig' \) 2>/dev/null)
  # the backups `omarchy plugin remove` keeps of every widget it removed
  while IFS= read -r p; do [ -n "$p" ] && leftovers+=("$p"); done \
    < <(find "$plugins" -mindepth 1 -maxdepth 1 -name '.*.bak.*' 2>/dev/null)

  if [ "${#leftovers[@]}" -eq 0 ]; then
    echo "nothing left over to purge"
  else
    echo
    echo "these are left over from earlier attempts:"
    printf '  %s\n' "${leftovers[@]}" | sed "s#$HOME#~#"
    if [ "$assume_yes" -eq 1 ]; then
      reply=y
    elif [ -e /dev/tty ] && printf 'delete them? [y/N] ' && read -r reply 2>/dev/null </dev/tty; then
      :
    else
      reply=n
      echo "(nothing to answer with: re-run with --purge --yes to delete them)"
    fi
    case "$reply" in
      y|Y|yes|YES) rm -rf -- "${leftovers[@]}" && echo "deleted ${#leftovers[@]} item(s)" ;;
      *) echo "left them alone" ;;
    esac
  fi
  # shell.json backups are your way back if the bar layout ever looks wrong, so they are only listed
  shopt -s nullglob
  backups=("$config"/shell.json.bak.ios-bar.*)
  shopt -u nullglob
  if [ "${#backups[@]}" -gt 0 ]; then
    echo
    echo "kept ${#backups[@]} shell.json backup(s) in ~/.config/omarchy (from before each install)."
    echo "if your bar layout looks wrong, restore the oldest one:"
    echo "  cp '$(printf '%s\n' "${backups[@]}" | sort | head -1 | sed "s#$HOME#\$HOME#")' ~/.config/omarchy/shell.json && omarchy restart shell"
  fi
fi

omarchy restart shell >/dev/null 2>&1 || echo "run: omarchy restart shell" >&2
echo
echo "removed: ${removed[*]:-none}"
[ "${#kept[@]}" -eq 0 ] || echo "kept: ${kept[*]}"
[ "$purge" -eq 1 ] || echo "if an earlier attempt left things behind, run: ./uninstall.sh --purge"
