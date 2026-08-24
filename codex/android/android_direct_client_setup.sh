#!/data/data/com.termux/files/usr/bin/bash
# 既存のAndroid専用鍵を使い、WSL2へ直接接続するghost_codex_directコマンドを作る。
# Windows OpenSSHやwsl.exeは使用しない。
set -euo pipefail

BASENAME="$(basename "$0")"
KEY_PATH="$HOME/.ssh/id_ed25519_ghost_codex"
BIN_DIR="$HOME/bin"
COMMAND_PATH="$BIN_DIR/ghost_codex_direct"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME <wsl_host> <ssh_port> <wsl_user> <remote_script> <working_directory> <session_name> [--dry-run]"
    echo "example: $BASENAME 192.168.10.5 2222 developer /home/developer/ghost/codex/bin/codex_remote_publish.sh /home/developer/ghost/codex codex"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -lt 6 ] || [ "$#" -gt 7 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

wsl_host="$1"
ssh_port="$2"
wsl_user="$3"
remote_script="$4"
working_directory="$5"
session_name="$6"
dry_run=0

if [ "$#" -eq 7 ]; then
  if [ "$7" != "--dry-run" ]; then
    usage "Unknown option: $7"
    exit 1
  fi
  dry_run=1
fi

for value in "$wsl_host" "$wsl_user" "$session_name"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    usage "Unsupported character in argument: $value"
    exit 1
  fi
done

if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1024 ] || [ "$ssh_port" -gt 65535 ]; then
  usage "SSH port must be between 1024 and 65535: $ssh_port"
  exit 1
fi

for path in "$remote_script" "$working_directory"; do
  if [[ ! "$path" =~ ^/[A-Za-z0-9_./-]+$ ]]; then
    usage "Remote paths must be simple absolute Linux paths: $path"
    exit 1
  fi
done

if [ ! -f "$KEY_PATH" ]; then
  echo "$BASENAME: Android private key does not exist: $KEY_PATH" >&2
  echo "Next: run android_client_setup.sh once to generate the device key." >&2
  exit 1
fi

{
  echo "[input]"
  echo "  WSL SSH:           $wsl_user@$wsl_host:$ssh_port"
  echo "  remote script:     $remote_script"
  echo "  working directory: $working_directory"
  echo "  tmux session:      $session_name"
  echo "[output]"
  echo "  command:           $COMMAND_PATH"
} >&2

if [ "$dry_run" -eq 1 ]; then
  echo "$BASENAME: --dry-run, not creating files" >&2
  echo "Next: run the same command without --dry-run." >&2
  exit 0
fi

mkdir -p "$BIN_DIR"
cat > "$COMMAND_PATH" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
exec ssh -p "$ssh_port" -i "$KEY_PATH" -t "$wsl_user@$wsl_host" "exec $remote_script $session_name $working_directory resume-last"
EOF
chmod 700 "$COMMAND_PATH"

echo "$BASENAME: setup complete" >&2
echo "Next: run $COMMAND_PATH after the WSL server and Hyper-V firewall are configured." >&2
