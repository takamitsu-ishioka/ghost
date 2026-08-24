#!/bin/bash
# Android -> Windows OpenSSH -> WSL2 -> tmux -> Codex の受け入れ側を読み取り専用で診断する。
# Linux側のコマンド、SSHサービス、22番ポート、Windows OpenSSHサービスを確認する。
set -uo pipefail

BASENAME="$(basename "$0")"

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

failures=0

check_command() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok\tcommand\t%s\t%s\n' "$1" "$(command -v "$1")"
  else
    printf 'ng\tcommand\t%s\tnot found\n' "$1"
    failures=$((failures + 1))
  fi
}

check_command codex
check_command tmux
check_command ssh

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  printf 'ok\twsl\tdistribution\t%s\n' "$WSL_DISTRO_NAME"
else
  printf 'ng\twsl\tdistribution\tWSL_DISTRO_NAME is empty\n'
  failures=$((failures + 1))
fi

if command -v powershell.exe >/dev/null 2>&1; then
  windows_status="$(powershell.exe -NoProfile -Command "\$s=Get-Service sshd -ErrorAction SilentlyContinue; if (\$null -eq \$s) {'missing'} else {\$s.Status.ToString()}" 2>/dev/null | tr -d '\r' | tail -n 1)"
  case "$windows_status" in
    Running) printf 'ok\twindows\tsshd\tRunning\n' ;;
    missing|'')
      printf 'ng\twindows\tsshd\tOpenSSH Server is not installed\n'
      failures=$((failures + 1))
      ;;
    *)
      printf 'ng\twindows\tsshd\t%s\n' "$windows_status"
      failures=$((failures + 1))
      ;;
  esac
else
  printf 'ng\twindows\tpowershell.exe\tWSL interop is unavailable\n'
  failures=$((failures + 1))
fi

if [ "$failures" -eq 0 ]; then
  echo "$BASENAME: all local checks passed" >&2
  echo "Next: test the connection from Android while both devices are on the same LAN." >&2
  exit 0
fi

echo "$BASENAME: $failures check(s) failed" >&2
echo "Next: follow ../README.ja.md from the first incomplete step." >&2
exit 1
