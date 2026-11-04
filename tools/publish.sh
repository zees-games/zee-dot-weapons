#!/bin/bash
# Publishes this pack to the dot-cloud CDN. Linked addons and README art stay out.
#   tools/publish.sh VERSION [extra publish_pack.sh flags, e.g. --token-file F --dry-run]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V=${1:?usage: tools/publish.sh VERSION [flags]}; shift
exec "$HERE/../dot-cloud/tools/publish_pack.sh" publish --source "$HERE" --id zee-dot-weapons --version "$V" \
    --exclude-dir addons --exclude-dir examples --exclude-dir tools --exclude-dir screenshots --exclude-dir docs --exclude-dir art-src --exclude-dir reports "$@"
