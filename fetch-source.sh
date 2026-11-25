#!/bin/bash
# Restore the binaries that are not tracked in git (listed in .gitignore under "CDN source pack") from the CDN (lock origin: prod; dev hash kept in manifest_sha256_by_origin), by sha256.
# source.lock.json pins every source file of this repo (published with gs-cloud tools/publish_pack.sh --source-lock);
# the one fetcher is gs-bootstrap/tools/fetch_lock.sh. Present files with the right hash are skipped.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="${GS_BOOTSTRAP:-$HERE/../gs-bootstrap}/tools/fetch_lock.sh"
[ -x "$tool" ] || { echo "fetch-source: gs-bootstrap is not beside this checkout; clone it or set GS_BOOTSTRAP" >&2; exit 2; }
exec "$tool" "$HERE/source.lock.json" --root "$HERE" "$@"
