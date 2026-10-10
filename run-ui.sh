#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: ./run-ui.sh' 'Open the live Agent Constellation UI in an isolated preview.' \
    'CONSTELLATION_CLAUDE_DIR and CONSTELLATION_CODEX_DIR select other session directories.'
  exit 0
fi
if (( $# )); then
  printf '%s\n' 'Unexpected argument. Use --help.' >&2
  exit 2
fi
constellation_preview=$(python3 -B "$repository_dir/tools/prepare_preview.py")
# The preview is a fresh temporary copy; remove it when the window closes.
trap 'rm -rf -- "$constellation_preview"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
qs -p "$constellation_preview"
