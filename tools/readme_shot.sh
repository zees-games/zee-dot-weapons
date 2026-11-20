#!/usr/bin/env bash
# tools/readme_shot.sh [--ids a,b] : the README studio shots, one PNG per weapon, into screenshots/readme/.
# A GPU job: heavy routes tools/*_shot.sh to staging02/staging (Vulkan on the NVIDIA card), so run it as
#   sudo -u gamedev heavy -- tools/readme_shot.sh
# from the checkout; never on llvmpipe. tools/gen_readme.sh calls it and turns the PNGs into docs/img/*.webp.
set -uo pipefail
cd "$(dirname "$0")/.."
out=screenshots/readme
mkdir -p "$out"; touch screenshots/.gdignore
xvfb-run -a -s "-screen 0 1280x720x24" timeout 600 godot --path . --resolution 1280x720 \
    res://tools/readme_shot.tscn -- --out "$PWD/$out" "$@" 2>&1 | grep -E 'READMESHOT|ERROR|SCRIPT ERROR' | head -80
n=$(ls "$out"/*.png 2>/dev/null | wc -l)
[ "$n" -gt 0 ] && echo "readme_shot: $n shot(s) in $out" || { echo "readme_shot: no shots" >&2; exit 1; }
