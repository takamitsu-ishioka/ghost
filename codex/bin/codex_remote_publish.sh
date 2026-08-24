#!/bin/bash
# Codex CLI を指定した tmux セッションで起動し、そのセッションへアタッチする。
# new は新しい会話、resume-last は指定ディレクトリで直近の会話を再開する。
# 同名の tmux セッションがある場合は、新しい Codex を起動せず既存セッションへ戻る。
set -euo pipefail

BASENAME="$(basename "$0")"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME <session_name> <working_directory> <new|resume-last> [--dry-run]"
    echo "example: $BASENAME codex /home/developer/ghost resume-last"
    echo "example: $BASENAME codex /home/developer/ghost new --dry-run"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

session_name="$1"
working_directory="$2"
mode="$3"
dry_run=0

if [ "$#" -eq 4 ]; then
  if [ "$4" != "--dry-run" ]; then
    usage "Unknown option: $4"
    exit 1
  fi
  dry_run=1
fi

if [[ ! "$session_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  usage "Invalid session name: $session_name"
  exit 1
fi

if [ ! -d "$working_directory" ]; then
  usage "Working directory does not exist: $working_directory"
  exit 1
fi

case "$mode" in
  new) codex_command=(codex) ;;
  resume-last) codex_command=(codex resume --last) ;;
  *)
    usage "Invalid mode: $mode"
    exit 1
    ;;
esac

if ! command -v tmux >/dev/null 2>&1; then
  echo "$BASENAME: tmux is not installed" >&2
  echo "Next: install tmux, then run this command again." >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "$BASENAME: codex is not installed or is not on PATH" >&2
  echo "Next: install Codex CLI, then run this command again." >&2
  exit 1
fi

{
  echo "[input]"
  echo "  session_name:      $session_name"
  echo "  working_directory: $working_directory"
  echo "  mode:              $mode"
  echo "[output]"
  echo "  tmux session:      $session_name"
  echo "  action:            create when absent, then attach"
} >&2

if [ "$dry_run" -eq 1 ]; then
  echo "$BASENAME: --dry-run, not creating or attaching to a tmux session" >&2
  echo "Next: run the same command without --dry-run." >&2
  exit 0
fi

if ! tmux has-session -t "$session_name" 2>/dev/null; then
  printf -v tmux_command '%q ' "${codex_command[@]}"
  tmux new-session -d -s "$session_name" -c "$working_directory" "$tmux_command"
  echo "$BASENAME: created tmux session $session_name" >&2
else
  echo "$BASENAME: tmux session $session_name already exists" >&2
fi

echo "$BASENAME: attaching; detach with Ctrl-b d" >&2
exec tmux attach-session -t "$session_name"
