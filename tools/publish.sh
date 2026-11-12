#!/bin/bash
# Publishes this pack to the dot-cloud CDN. Linked addons and README art stay out.
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --token-file F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
# addons/zee_weapons is the code a host mounts from this pack as an overlay, so it goes in.
# Every addon folder but addons/zee_weapons stays out, by folder name, so a copy with links resolved (heavy's staging box) packs the same.
# Top-level examples/tools/docs/... are the publisher's exclude_roots; --exclude-dir matches at any depth and dropped addons/zee_weapons/tools.
EX=(); for d in "$HERE"/addons/*/; do n="$(basename "$d")"; [ "$n" = zee_weapons ] || EX+=(--exclude-dir "$n"); done
"$HERE/../dot-cloud/tools/publish_pack.sh" publish --source "$HERE" --id zee-dot-weapons --version "$V" \
    "${EX[@]}" "$@"
