# 原本(日本語)から二次情報(英語版)を作り直し、リポジトリへ反映する。
# docs/CLAUDE.md の「言語・書式の変換」規則の実装。
.PHONY: push

push:
	./tools/claude_md_sync.sh
	./tools/document_translate.sh < note/0_prologue/article_ja.md > note/0_prologue/article_en.md
