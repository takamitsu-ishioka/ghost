# AndroidからLAN内のCodexを操作する

## 目的

AndroidからWindowsへ公開鍵認証でSSH接続し、Windows上のWSL2で動くCodexのtmuxセッションへ入る。

```text
Android / Termux
    | SSH（LAN、公開鍵認証）
    v
Windows OpenSSH Server
    | wsl.exe
    v
WSL2 / tmux / Codex CLI
```

ルーターのポート開放は行わない。WindowsファイアウォールもPrivateネットワークからのTCP 22だけを許可する。

Codexは`developer`自身ではなく、読み取り専用ユーザー`ghost-codex-reader`として動く。chrootは使わず、Unixの標準的なファイル権限とACLだけで「このリポジトリは読めるが、developerの他のファイルや書き込みには一切触れない」を実現している。詳細は[../docs/designs/codex_implementation_plan_ja.md](../docs/designs/codex_implementation_plan_ja.md)を参照。

## 0. 読み取り専用ユーザーを作る（自動、初回のみ）

```bash
cd /home/developer/ghost
./bin/ghost_reader_user_setup.sh ghost-codex-reader --dry-run
./bin/ghost_reader_user_setup.sh ghost-codex-reader
```

## 1. WSL2側を確認する（自動）

```bash
cd /home/developer/ghost
./codex/bin/codex_remote_check.sh
```

最初はWindows OpenSSHが未設定なので失敗してよい。`codex`、`tmux`、`ssh`が見つかることを確認する。

## 2. AndroidにTermuxを用意する（手動）

AndroidにTermuxをインストールする。Termux内で次を実行する。

```bash
pkg update
pkg install openssh
```

`android_client_setup.sh`を、このリポジトリからAndroidのTermuxへコピーする。この最初のコピーだけは、USB、共有フォルダー、Androidのファイル選択など、人が選んだ方法で行う。

## 3. Androidの鍵と接続コマンドを作る（自動）

Windows PCのPrivate IPv4アドレスをWindowsで確認する。

```powershell
ipconfig
```

Termuxで、実際のWindowsユーザー名とIPv4アドレスに置き換えて実行する。

```bash
bash android_client_setup.sh kisab 192.168.1.20 Ubuntu ghost-codex-reader /home/developer/ghost/codex/bin/codex_remote_publish.sh /home/developer/ghost codex
```

このコマンドは秘密鍵をAndroid内に作り、公開鍵だけを画面へ出す。表示された1行をWindows上の `id_ed25519_ghost_codex.pub` へ保存する。秘密鍵はコピーしない。

## 4. Windows OpenSSHを設定する（半自動）

ここはWindowsの管理者権限が必要なので、人が管理者PowerShellを開く。

管理者PowerShellで、リポジトリと公開鍵の実際のWindowsパスに置き換えて実行する。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd \\wsl.localhost\Ubuntu\home\developer\ghost\codex\windows
.\windows_ssh_server_setup.ps1 C:\path\to\id_ed25519_ghost_codex.pub -DryRun
.\windows_ssh_server_setup.ps1 C:\path\to\id_ed25519_ghost_codex.pub
```

スクリプトが自動化するもの：

- Windows OpenSSH Serverのインストール
- `sshd` の自動起動と開始
- Privateネットワークだけを対象としたTCP 22の受信許可
- 現在のWindows管理者ユーザーへのAndroid公開鍵の登録

人が行うもの：

- UACと管理者権限の承認
- Android公開鍵ファイルの場所の指定
- Windowsネットワークが「プライベート」であることの確認

## 5. Androidから接続する（自動）

Termuxで次を実行する。

```bash
~/bin/ghost_codex
```

初回接続時だけ、表示されたWindowsホスト鍵のフィンガープリントをWindows側で確認してから受け入れる。

接続すると、tmuxセッション `codex` がなければ `codex resume --last` で作成し、あればそのまま再接続する。

切断せずAndroidだけを閉じたい場合は、tmuxで次を押す。

```text
Ctrl-b d
```

## 6. 最終確認（自動 + 手動）

WSL2で再度診断する。

```bash
cd /home/developer/ghost
./codex/bin/codex_remote_check.sh
```

Androidから接続できたら、Wi-Fiをオフにしてモバイル回線だけにする。この状態で接続できないことを確認する。接続できる場合は、ルーターでTCP 22が公開されていないか確認して閉じる。

## 既知の課題（優先度順）

- **（対応済み）副作用の禁止**: Codexは読み取り専用ユーザー`ghost-codex-reader`として動くため、developer自身のファイルへの書き込みや`git commit`/`push`は権限レベルで失敗する。判断ではなく権限で止める。
- **（優先度: 低）キーの意味論的不一致**: tmux上でsubmit-key（Enter vs Alt+Enter/Shift+Enter）やexit-key（Ctrl+Dの回数など、ツールによって異なる）がGhost Clientの意図通りに伝わらない場合がある。まだ調査・対応していない。

## 制約

- PCが起動し、Windows OpenSSHとWSL2が利用できる必要がある。
- Windowsユーザーのパスワードログイン自体は、このスクリプトでは無効化しない。既存のWindows SSH利用者を誤って締め出さないためである。Android側の接続コマンドは専用鍵を明示して使用する。
- Androidの秘密鍵を紛失した場合は、Windowsの `administrators_authorized_keys` から対応する公開鍵を削除する。
