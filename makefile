# 原本(日本語)から二次情報(英語版)を作り直し、リポジトリへ反映する。
# docs/CLAUDE.md の「言語・書式の変換」規則の実装。
.PHONY: push

ARTICLE_JA := note/0_prologue/article_ja.md
ARTICLE_EN := note/0_prologue/article_en.md
AGENT_TRANSLATION_MAX_LINES := 1000

push:
	./tools/claude_md_sync.sh
	@if git ls-files --error-unmatch -- "$(ARTICLE_JA)" >/dev/null 2>&1 && \
		git diff --quiet HEAD -- "$(ARTICLE_JA)"; then \
		echo "Skipping translation: $(ARTICLE_JA) is already committed." >&2; \
	elif lines=$$(awk 'END { print NR }' "$(ARTICLE_JA)") && \
		[ "$$lines" -gt "$(AGENT_TRANSLATION_MAX_LINES)" ]; then \
		echo "Skipping agent translation: $(ARTICLE_JA) has $$lines lines (limit: $(AGENT_TRANSLATION_MAX_LINES)). Please provide a manual translation in $(ARTICLE_EN)." >&2; \
	else \
		./tools/document_translate.sh < "$(ARTICLE_JA)" > "$(ARTICLE_EN)"; \
	fi
