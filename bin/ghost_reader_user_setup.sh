#!/bin/bash
# 指定した名前の読み取り専用Unixユーザーを作成し、このリポジトリの親ディレクトリに
# 対する走査のみの権限、リポジトリ本体に対する再帰的な読み取り専用ACLを付与する。
# chrootは使わない。書き込み・sudo・developerグループへの参加は一切許可しない。
# 同じ名前のユーザーやACLが既に存在する場合はスキップする。
set -euo pipefail

BASENAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OWNER_HOME="$(dirname "$REPO_DIR")"

usage() {
  {
    echo "$BASENAME: $1"
    echo "usage: $BASENAME <username> [--dry-run]"
    echo "example: $BASENAME ghost-claude-reader"
    echo "example: $BASENAME ghost-codex-reader --dry-run"
    echo
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
  } >&2
}

dry_run=0
args=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    -*)
      usage "Unknown option: $arg"
      exit 1
      ;;
    *) args+=("$arg") ;;
  esac
done

if [ "${#args[@]}" -ne 1 ]; then
  usage "Wrong number of arguments"
  exit 1
fi
username="${args[0]}"

if [[ ! "$username" =~ ^[a-z][a-z0-9-]{0,31}$ ]]; then
  usage "Invalid username: $username"
  exit 1
fi

user_home="/home/$username"

# --- package ---
package_already=0
if dpkg-query -W -f='${Status}' acl 2>/dev/null | grep -q 'install ok installed'; then
  package_already=1
fi

# --- user ---
user_already=0
if id -u "$username" >/dev/null 2>&1; then
  user_already=1
fi

# --- ACL ---
acl_already=0
if command -v getfacl >/dev/null 2>&1; then
  if getfacl -p "$OWNER_HOME" 2>/dev/null | grep -qE "^user:$username:-?-?x" \
     && getfacl -p "$REPO_DIR" 2>/dev/null | grep -qE "^user:$username:r-?x"; then
    acl_already=1
  fi
fi

# --- git safe.directory ---
safe_dir_already=0
if [ "$user_already" -eq 1 ] \
   && sudo -u "$username" git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$REPO_DIR"; then
  safe_dir_already=1
fi

{
  echo "[input]"
  echo "  username: $username"
  echo "  owner home (traverse-only): $OWNER_HOME"
  echo "  repository (read+traverse, recursive): $REPO_DIR"
  echo "[output]"
  echo "  package acl: $([ "$package_already" -eq 1 ] && echo 'already installed' || echo 'will install')"
  echo "  user $username: $([ "$user_already" -eq 1 ] && echo 'already exists' || echo "will create, home=$user_home, shell=/bin/bash, no password, not in sudo/developer group")"
  echo "  ACL grant: $([ "$acl_already" -eq 1 ] && echo 'already present' || echo 'will add (idempotent, safe to reapply)')"
  echo "  git safe.directory: $([ "$safe_dir_already" -eq 1 ] && echo 'already registered' || echo 'will register')"
} >&2

if [ "$dry_run" -eq 1 ]; then
  echo "$BASENAME: --dry-run, not making changes" >&2
  echo "Next: run the same command without --dry-run." >&2
  exit 0
fi

if [ "$package_already" -eq 0 ]; then
  sudo apt-get update
  sudo apt-get install -y acl
fi

if [ "$user_already" -eq 0 ]; then
  sudo adduser --system --group --home "$user_home" --shell /bin/bash --disabled-password "$username"
  echo "$BASENAME: created user $username" >&2
fi

sudo setfacl -m "u:$username:--x" "$OWNER_HOME"
sudo setfacl -R -m "u:$username:rX" "$REPO_DIR"
sudo setfacl -R -d -m "u:$username:rX" "$REPO_DIR"
echo "$BASENAME: granted $username traverse-only on $OWNER_HOME and recursive read+traverse (with default ACL) on $REPO_DIR" >&2

# git refuses to operate in a repository it doesn't own ("dubious ownership") unless
# told otherwise; the reader account only ever needs read-only git commands here.
if ! sudo -u "$username" git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$REPO_DIR"; then
  sudo -u "$username" git config --global --add safe.directory "$REPO_DIR"
  echo "$BASENAME: registered $REPO_DIR as a git safe.directory for $username" >&2
fi

{
  echo ""
  echo "Next: verify with:"
  echo "  sudo -u $username git -C $REPO_DIR status        # should succeed"
  echo "  sudo -u $username touch $REPO_DIR/x               # should fail"
  echo "  sudo -u $username cat $OWNER_HOME/.ssh/authorized_keys  # should fail"
} >&2
