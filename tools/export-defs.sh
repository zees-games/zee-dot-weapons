#!/usr/bin/env bash
# Rewrites weapons/*.tres and provides.json from the code table (ZeeDefExport).
# The suite fails when they are stale. Goes through heavy on a shared machine.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
exec timeout 120 "${GODOT:-godot}" --headless --path . --script res://tools/export_defs.gd
