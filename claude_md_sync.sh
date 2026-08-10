#!/bin/bash
# ~/.claude/CLAUDE.md (_CLAUDE.md からの symlink) の実体を CLAUDE.md へコピーする。
# git はシンボリックリンクをリンクのまま push してしまうため、
# 実際にリポジトリへ含める（push する）のは実体をコピーした CLAUDE.md 側。
# _CLAUDE.md を更新したあと commit 前に実行して同期すること。
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "claude_md_sync.sh: 引数は不要です" >&2
  echo "usage: claude_md_sync.sh" >&2
  echo "example: claude_md_sync.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp -L "$SCRIPT_DIR/_CLAUDE.md" "$SCRIPT_DIR/CLAUDE.md"
echo "synced: $SCRIPT_DIR/CLAUDE.md <- $(readlink "$SCRIPT_DIR/_CLAUDE.md")" >&2
