# 案3: Windows OpenSSHを介さずAndroidからWSL2へ接続する

## 目的

Windows OpenSSHと `wsl.exe` をSSH通信経路から外し、AndroidからWSL2の `sshd` へ直接入る。

```text
Android / Termux
    | SSH（LAN、TCP 2222、公開鍵認証）
    v
WSL2 / sshd
    |
    v
tmux / Codex CLI
```

WSL2自体はWindows上のVMなので、Windows OSを物理的に排除する案ではない。排除するのはWindows OpenSSHによる中継とWindows→WSLのリモートコマンド境界である。

Microsoftの公式資料によれば、Windows 11 22H2以降では `networkingMode=mirrored` によりLANからWSLへ直接接続できる。ただし、Hyper-V firewallの受信許可はホスト側で一度設定する必要がある。

- https://learn.microsoft.com/windows/wsl/networking#mirrored-mode-networking
- https://learn.microsoft.com/windows/wsl/wsl-config

## 手順

### 0. 読み取り専用ユーザーを作る（自動、初回のみ）

```bash
cd /home/developer/ghost
./bin/ghost_reader_user_setup.sh ghost-codex-reader --dry-run
./bin/ghost_reader_user_setup.sh ghost-codex-reader
```

chrootは使わず、`ghost-codex-reader`にこのリポジトリへの読み取り専用ACLだけを付与する（`developer`の`~/.ssh`や`~/.claude`等には一切到達できない）。詳細は[../docs/designs/codex_implementation_plan_ja.md](../docs/designs/codex_implementation_plan_ja.md)を参照。

### 1. WSLの直接SSHを準備する（自動）

WSLでdry-runする。

```bash
cd /home/developer/ghost
./codex/bin/direct_wsl_server_setup.sh codex/android/id_ed25519_ghost_codex.pub 2222 --dry-run
```

問題がなければ本実行する。

```bash
./codex/bin/direct_wsl_server_setup.sh codex/android/id_ed25519_ghost_codex.pub 2222
```

自動化するもの：

- `openssh-server` と `tmux` の導入
- Android公開鍵の `ghost-codex-reader` の `authorized_keys` への登録（`developer`自身のものではない）
- WSLのSSH専用ポート `2222`、`AllowUsers ghost-codex-reader`
- パスワード認証とrootログインの無効化
- `ssh` サービスの自動起動

### 2. WSLをmirrored networkingへ変更する（半自動）

管理者PowerShellでdry-runする。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd \\wsl.localhost\Ubuntu\home\developer\ghost\codex\windows
.\wsl_mirrored_network_setup.ps1 2222 -DryRun
```

問題がなければ本実行する。

```powershell
.\wsl_mirrored_network_setup.ps1 2222
```

このスクリプトは `%USERPROFILE%\.wslconfig` の既存内容を保ちながら `[wsl2]` の `networkingMode=mirrored` を設定し、Hyper-V firewallでWSLのTCP 2222だけを許可する。

### 3. WSLを再起動する（手動）

すべてのWSL作業を保存してから、PowerShellで実行する。

```powershell
wsl --shutdown
```

この操作は実行中の全WSLディストリビューションを停止するため、自動化しない。

その後、Ubuntuを起動し直す。

### 4. Androidの直接接続コマンドを作る（自動）

`android_direct_client_setup.sh` をTermuxへコピーし、実行する。

```bash
bash ~/android_direct_client_setup.sh 192.168.10.5 2222 ghost-codex-reader /home/developer/ghost/codex/bin/codex_remote_publish.sh /home/developer/ghost/codex codex
```

### 5. 接続する

```bash
~/bin/ghost_codex_direct
```

初回はWSL側のホスト鍵指紋を、WSLで次のように取得した値と照合する。

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

## 案2からの移行

案3が動作するまで、Windows OpenSSHは削除しない。案3の接続確認後、案2のWindows OpenSSHを停止・削除するかは別作業として判断する。

案3では次を使用しない。

- Windowsの `sshd`
- `C:\ProgramData\ssh\administrators_authorized_keys`
- Androidの `~/bin/ghost_codex`
- Windows上での `wsl.exe` リモートコマンド
