#!/bin/bash
# ~/.claude/CLAUDE.md / CLAUDE.en.md (docs/_CLAUDE.md / docs/_CLAUDE.en.md からの symlink) の
# 実体を docs/CLAUDE.ja.md / docs/CLAUDE.md へコピーする（英語版 CLAUDE.md が正本）。
# git はシンボリックリンクをリンクのまま push してしまうため、
# 実際にリポジトリへ含める（push する）のは実体をコピーした側。
# docs/_CLAUDE.md / docs/_CLAUDE.en.md を更新したあと commit 前に実行して同期すること。
set -euo pipefail

if [ "$#" -ne 0 ]; then
  echo "claude_md_sync.sh: 引数は不要です" >&2
  echo "usage: claude_md_sync.sh" >&2
  echo "example: claude_md_sync.sh" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(cd "$SCRIPT_DIR/../docs" && pwd)"

cp -L "$DOCS_DIR/_CLAUDE.md" "$DOCS_DIR/CLAUDE.ja.md"
echo "synced: $DOCS_DIR/CLAUDE.ja.md <- $(readlink "$DOCS_DIR/_CLAUDE.md")" >&2

cp -L "$DOCS_DIR/_CLAUDE.en.md" "$DOCS_DIR/CLAUDE.md"
echo "synced: $DOCS_DIR/CLAUDE.md <- $(readlink "$DOCS_DIR/_CLAUDE.en.md")" >&2
