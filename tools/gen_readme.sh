#!/usr/bin/env bash
# Regenerate the README's weapon gallery: studio renders of every weapon (on a GPU box) and the stat tables.
#
#   tools/gen_readme.sh                  capture every weapon, convert, rewrite README.md
#   tools/gen_readme.sh --ids a,b        recapture only these, then rewrite README.md
#   tools/gen_readme.sh --text           no capture: rewrite README.md from the data only (after a tuning change)
#   tools/gen_readme.sh --check          exit 1 if README.md is out of date with the data (CI)
#
# The capture is tools/readme_shot.sh (tools/readme_shot.tscn, settings in tools/readme.cfg). It must render on a
# real GPU, never llvmpipe or --headless, so it goes through `heavy`, which hands tools/*_shot.sh to a GPU box
# (dot-bootstrap tools/gpu.sh) and copies the new PNGs back into screenshots/readme/. Each PNG becomes
# docs/img/<id>.webp (1280 px) and docs/img/<id>_thumb.webp (320 px) for the summary table.
# Text and stats: tools/gen_readme.py, words from docs/readme/weapons.yml. Look at every image before committing.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=all
ids=""
while [[ $# -gt 0 ]]; do
	case $1 in
		--text) mode=text ;;
		--check) exec python3 tools/gen_readme.py --check ;;
		--ids) ids=$2; shift ;;
		*) echo "gen_readme.sh: unknown argument $1" >&2; exit 2 ;;
	esac
	shift
done

if [[ $mode == all ]]; then
	command -v magick >/dev/null || { echo "gen_readme.sh: needs ImageMagick 7 (magick) with WebP" >&2; exit 2; }
	rm -f screenshots/readme/*.png
	args=()
	[[ -n $ids ]] && args=(--ids "$ids")
	if command -v heavy >/dev/null; then
		heavy -- tools/readme_shot.sh "${args[@]}"
	else
		echo "gen_readme.sh: no heavy here; rendering locally (needs a real GPU)" >&2
		tools/readme_shot.sh "${args[@]}"
	fi
	mkdir -p docs/img
	[[ -e docs/img/.gdignore ]] || : > docs/img/.gdignore
	n=0
	for png in screenshots/readme/*.png; do
		[[ -e $png ]] || continue
		id=$(basename "$png" .png)
		magick "$png" -strip -resize '1280x>' -quality 82 -define webp:method=6 "docs/img/$id.webp"
		magick "$png" -strip -resize 320x -quality 80 -define webp:method=6 "docs/img/${id}_thumb.webp"
		n=$((n + 1))
	done
	[[ $n -gt 0 ]] || { echo "gen_readme.sh: the capture produced no images" >&2; exit 1; }
	echo "gen_readme.sh: $n image(s) in docs/img"
fi
python3 tools/gen_readme.py
