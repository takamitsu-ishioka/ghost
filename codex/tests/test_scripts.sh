#!/bin/bash
# ghost/codex 配下のbashスクリプトの構文と、変更を伴わないdry-runを検証する。
set -euo pipefail

BASENAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
GHOST_DIR="$(cd "$CODEX_DIR/.." && pwd)"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME"
    echo "example: $BASENAME"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -ne 0 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

bash -n "$CODEX_DIR"/bin/*.sh "$CODEX_DIR"/android/*.sh "$GHOST_DIR/bin/ghost_reader_user_setup.sh"

"$GHOST_DIR/bin/ghost_reader_user_setup.sh" ghost-codex-reader --dry-run >/dev/null

"$CODEX_DIR/bin/codex_remote_publish.sh" \
  codex-test "$GHOST_DIR" resume-last --dry-run >/dev/null

bash "$CODEX_DIR/android/android_client_setup.sh" \
  windows-user 192.0.2.1 Ubuntu ghost-codex-reader \
  "$CODEX_DIR/bin/codex_remote_publish.sh" "$GHOST_DIR" codex-test \
  --dry-run >/dev/null

"$CODEX_DIR/bin/direct_wsl_server_setup.sh" \
  "$CODEX_DIR/android/id_ed25519_ghost_codex.pub" 2222 --dry-run >/dev/null

echo "$BASENAME: all tests passed" >&2
echo "Next: follow $CODEX_DIR/README.ja.md on the target devices." >&2
