#!/bin/bash
# WSL2のOpenSSH Serverを専用ポートで起動し、Android公開鍵だけでログインできるようにする。
# 読み取り専用ユーザー ghost-codex-reader の authorized_keys と、そのユーザーだけを
# 許可するsshd_config.dドロップインを冪等に更新する
# （ghost-codex-reader は bin/ghost_reader_user_setup.sh で事前に作成しておくこと）。
set -euo pipefail

BASENAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER_USER="ghost-codex-reader"
READER_SETUP="$SCRIPT_DIR/../../bin/ghost_reader_user_setup.sh"
SSH_DIR="/home/$READER_USER/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
SSHD_DROP_IN="/etc/ssh/sshd_config.d/99-ghost-codex-direct.conf"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME <android_public_key_path> <ssh_port> [--dry-run]"
    echo "example: $BASENAME codex/android/id_ed25519_ghost_codex.pub 2222"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage "Wrong number of arguments"
  exit 1
fi

public_key_path="$1"
ssh_port="$2"
dry_run=0

if [ "$#" -eq 3 ]; then
  if [ "$3" != "--dry-run" ]; then
    usage "Unknown option: $3"
    exit 1
  fi
  dry_run=1
fi

if [ ! -f "$public_key_path" ]; then
  usage "Public key does not exist: $public_key_path"
  exit 1
fi

if [[ ! "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1024 ] || [ "$ssh_port" -gt 65535 ]; then
  usage "SSH port must be between 1024 and 65535: $ssh_port"
  exit 1
fi

if ! fingerprint="$(ssh-keygen -l -f "$public_key_path" 2>&1)"; then
  usage "Invalid public key: $fingerprint"
  exit 1
fi

key_line="$(tr -d '\r\n' < "$public_key_path")"
key_material="$(awk '{print $1, $2}' <<<"$key_line")"

{
  echo "[input]"
  echo "  public key:  $public_key_path"
  echo "  fingerprint: $fingerprint"
  echo "  Linux user:  $READER_USER (read-only, no chroot, no sudo)"
  echo "  SSH port:    $ssh_port"
  echo "[output]"
  echo "  packages:    openssh-server, tmux"
  echo "  key file:    $AUTH_KEYS"
  echo "  sshd config: $SSHD_DROP_IN"
  echo "  service:     ssh (enabled / running)"
} >&2

if [ "$dry_run" -eq 1 ]; then
  echo "$BASENAME: --dry-run, not making changes" >&2
  echo "Next: run the same command without --dry-run." >&2
  exit 0
fi

if ! id -u "$READER_USER" >/dev/null 2>&1; then
  echo "$BASENAME: user $READER_USER does not exist" >&2
  echo "Next: run $READER_SETUP $READER_USER first." >&2
  exit 1
fi

missing_packages=()
for package in openssh-server tmux; do
  if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
    missing_packages+=("$package")
  fi
done

if [ "${#missing_packages[@]}" -gt 0 ]; then
  sudo apt-get update
  sudo apt-get install -y "${missing_packages[@]}"
fi

sudo -u "$READER_USER" mkdir -p "$SSH_DIR"
sudo -u "$READER_USER" chmod 700 "$SSH_DIR"
sudo -u "$READER_USER" touch "$AUTH_KEYS"
sudo -u "$READER_USER" chmod 600 "$AUTH_KEYS"
if ! sudo -u "$READER_USER" grep -qF "$key_material" "$AUTH_KEYS"; then
  printf '%s\n' "$key_line" | sudo -u "$READER_USER" tee -a "$AUTH_KEYS" >/dev/null
fi

{
  echo "Port $ssh_port"
  echo "PubkeyAuthentication yes"
  echo "PasswordAuthentication no"
  echo "KbdInteractiveAuthentication no"
  echo "PermitRootLogin no"
  echo "AllowUsers $READER_USER"
} | sudo tee "$SSHD_DROP_IN" >/dev/null

# Not "sudo sshd -t" here: ssh.service's own unit already declares
# RuntimeDirectory=sshd (creates /run/sshd, wiped on every WSL restart since
# /run is tmpfs) and ExecStartPre=/usr/sbin/sshd -t, so it does the same
# config check with the right runtime directory in place; a manual
# out-of-band "sshd -t" fails here with "Missing privilege separation
# directory: /run/sshd" because it never gets that directory.
sudo systemctl enable --now ssh

echo "$BASENAME: setup complete" >&2
echo "Next: configure WSL mirrored networking and its Hyper-V firewall rule, then run wsl --shutdown." >&2
