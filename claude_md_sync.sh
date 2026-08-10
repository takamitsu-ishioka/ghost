#!/bin/bash
# ~/.claude/CLAUDE.md / CLAUDE.en.md (_CLAUDE.md / _CLAUDE.en.md からの symlink) の実体を
# CLAUDE.ja.md / CLAUDE.md へコピーする（英語版 CLAUDE.md が正本）。
# git はシンボリックリンクをリンクのまま push してしまうため、
# 実際にリポジトリへ含める（push する）のは実体をコピーした側。
# _CLAUDE.md / _CLAUDE.en.md を更新したあと commit 前に実行して同期すること。
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "claude_md_sync.sh: 引数は不要です" >&2
  echo "usage: claude_md_sync.sh" >&2
  echo "example: claude_md_sync.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp -L "$SCRIPT_DIR/_CLAUDE.md" "$SCRIPT_DIR/CLAUDE.ja.md"
echo "synced: $SCRIPT_DIR/CLAUDE.ja.md <- $(readlink "$SCRIPT_DIR/_CLAUDE.md")" >&2

cp -L "$SCRIPT_DIR/_CLAUDE.en.md" "$SCRIPT_DIR/CLAUDE.md"
echo "synced: $SCRIPT_DIR/CLAUDE.md <- $(readlink "$SCRIPT_DIR/_CLAUDE.en.md")" >&2
