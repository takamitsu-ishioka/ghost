#!/data/data/com.termux/files/usr/bin/bash
# Termux に SSH鍵と ghost_codex 接続コマンドを作成する。
# 作成した公開鍵は標準出力へ出し、秘密鍵はAndroid端末の外へ出さない。
set -euo pipefail

BASENAME="$(basename "$0")"
SSH_DIR="$HOME/.ssh"
KEY_PATH="$SSH_DIR/id_ed25519_ghost_codex"
BIN_DIR="$HOME/bin"
COMMAND_PATH="$BIN_DIR/ghost_codex"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME <windows_user> <windows_host> <wsl_distribution> <wsl_user> <remote_script> <working_directory> <session_name> [--dry-run]"
    echo "example: $BASENAME kisab 192.168.1.20 Ubuntu developer /home/developer/ghost/codex/bin/codex_remote_publish.sh /home/developer/ghost codex"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -lt 7 ] || [ "$#" -gt 8 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

windows_user="$1"
windows_host="$2"
wsl_distribution="$3"
wsl_user="$4"
remote_script="$5"
working_directory="$6"
session_name="$7"
dry_run=0

if [ "$#" -eq 8 ]; then
  if [ "$8" != "--dry-run" ]; then
    usage "Unknown option: $8"
    exit 1
  fi
  dry_run=1
fi

for value in "$windows_user" "$windows_host" "$wsl_distribution" "$wsl_user" "$session_name"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    usage "Unsupported character in argument: $value"
    exit 1
  fi
done

for path in "$remote_script" "$working_directory"; do
  if [[ ! "$path" =~ ^/[A-Za-z0-9_./-]+$ ]]; then
    usage "Remote paths must be simple absolute Linux paths: $path"
    exit 1
  fi
done

{
  echo "[input]"
  echo "  Windows SSH:       $windows_user@$windows_host"
  echo "  WSL:               $wsl_distribution / $wsl_user"
  echo "  remote script:     $remote_script"
  echo "  working directory: $working_directory"
  echo "  tmux session:      $session_name"
  echo "[output]"
  echo "  private key:       $KEY_PATH"
  echo "  public key:        $KEY_PATH.pub and stdout"
  echo "  command:           $COMMAND_PATH"
} >&2

if [ "$dry_run" -eq 1 ]; then
  echo "$BASENAME: --dry-run, not creating files" >&2
  echo "Next: run the same command without --dry-run." >&2
  exit 0
fi

command -v ssh >/dev/null 2>&1 || {
  echo "$BASENAME: ssh is not installed" >&2
  echo "Next: run pkg install openssh, then run this command again." >&2
  exit 1
}

mkdir -p "$SSH_DIR" "$BIN_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$KEY_PATH" ]; then
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "android-ghost-codex" -q
  echo "$BASENAME: generated $KEY_PATH" >&2
else
  echo "$BASENAME: reusing $KEY_PATH" >&2
fi

cat > "$COMMAND_PATH" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec ssh -i "$KEY_PATH" -t "$windows_user@$windows_host" "wsl.exe -d $wsl_distribution -u $wsl_user --cd $working_directory -- /bin/bash -lc 'exec $remote_script $session_name $working_directory resume-last'"
EOF
chmod 700 "$COMMAND_PATH"

cat "$KEY_PATH.pub"
echo "$BASENAME: setup complete" >&2
echo "Next: copy the public key printed above to the Windows PC, then run the Windows setup script as Administrator." >&2
