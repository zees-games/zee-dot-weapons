#!/usr/bin/env bash
#
# Copy the weapon art a game needs into the game (or check that it is all there).
#
#   tools/sync-art.sh ../game-arena            # copy what ZeeWeaponArtTable names
#   tools/sync-art.sh ../game-arena --check    # copy nothing; exit 1 if anything is missing or differs
#   tools/sync-art.sh ../game-arena --arms     # also the arms model (style = &"model")
#
# The sources are found from the game's own addons/ links: zee_weapons (and zed_weapons when
# linked) resolve to their repositories, whose assets/ hold the art. The list is the table's
# (`ZeeWeaponArtTable.model_paths()`), never a folder copy, so a game vendors what it uses.
# Why the copy exists at all: addons/zee_weapons/tools/zee_art_sync.gd.
set -euo pipefail

# The game directory may come before or after the flags.
GAME=""
FLAGS=()
for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --check|--arms) FLAGS+=("$arg") ;;
        -*) echo "unknown option: $arg (usage: tools/sync-art.sh <game-dir> [--check] [--arms])" >&2; exit 2 ;;
        *) GAME="$arg" ;;
    esac
done
[ -n "$GAME" ] || { echo "usage: tools/sync-art.sh <game-dir> [--check] [--arms]" >&2; exit 2; }
GAME="$(cd -- "$GAME" && pwd)"
GODOT="${GODOT:-godot}"
FROM=()

for addon in zee_weapons zed_weapons; do
    link="$GAME/addons/$addon"
    [ -e "$link" ] || continue
    # addons/<name> -> <repo>/addons/<name>, so the repo is two levels up from the target
    FROM+=(--from "$(cd "$(readlink -f "$link")/../.." && pwd)")
done

[ "${#FROM[@]}" -gt 0 ] || { echo "$GAME has no addons/zee_weapons link" >&2; exit 2; }

timeout 300 "$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
timeout 300 "$GODOT" --headless --path "$GAME" \
    --script res://addons/zee_weapons/tools/zee_art_sync.gd -- "${FROM[@]}" "${FLAGS[@]}"
