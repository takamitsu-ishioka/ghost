#!/bin/bash
# 日本語Markdown文書(stdin)を英語Markdown(stdout)へ翻訳する。
# 原本(日本語)から英語版を作るための部品。実体は document_translate.py。
# claude -p を "## " 見出し単位のチャンクごとに呼び出し、
# 改行保存規約(行末のゼロ幅スペース+半角スペース2つ等)を含めた
# 行単位の構造を保ったまま翻訳する。
set -euo pipefail

BASENAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME"
    echo "example: $BASENAME < note/0_prologue/article_ja.md > note/0_prologue/article_en.md"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -ne 0 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

exec python3 "$SCRIPT_DIR/document_translate.py"
