# 残作業（Ghost読み取り専用ユーザー化 / Codex direct-wsl 接続）

`ghost-claude-reader` / `ghost-codex-reader` の実装・WSL側の設定・コミット/プッシュは完了済み。
残っているのは、私（Claude Code）からは実行できない、ユーザー本人の対話操作が必要な手順のみ。

## 1. Windows側（管理者PowerShell、半自動）— Codex direct-wsl (案3) 用

mirrored networkingがまだ未設定（WSL側は`172.26.26.218`というNAT内部アドレスのまま）。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd \\wsl.localhost\Ubuntu\home\developer\ghost\codex\windows
.\wsl_mirrored_network_setup.ps1 2222 -DryRun
.\wsl_mirrored_network_setup.ps1 2222
```

作業を保存してから:

```powershell
wsl --shutdown
```

（Ubuntuを起動し直す）

## 2. Termux側（Android）— Codex direct-wsl (案3) 用

秘密鍵は既存のものを再利用（作り直し不要）。接続先ユーザーを`ghost-codex-reader`に更新した接続コマンドを再生成する。

```bash
bash ~/android_direct_client_setup.sh <WindowsPCのLAN IP> 2222 ghost-codex-reader /home/developer/ghost/codex/bin/codex_remote_publish.sh /home/developer/ghost/codex codex
```

`<WindowsPCのLAN IP>` はmirrored networking有効化後のPCのIPv4アドレス（以前は`192.168.10.5`を使用 — 変わっていないか要確認）。

初回のみWSL側のホスト鍵指紋を照合してから接続する。

```bash
~/bin/ghost_codex_direct
```

## 3. Claude Code / Codex CLI 自身の資格情報（対話ログイン、owner本人のみ実行可）

```bash
sudo -u ghost-claude-reader claude
```
（初回のみ対話的にOAuthログイン。以後は`ghost publish`から自動的に使われる）

```bash
sudo -u ghost-codex-reader codex login
```
（Codex CLIの認証フローに相当するもの。コマンド名は要確認）

## 4. 未実施の実機確認

- 別マシンから`ghost trust`→`ghost join <this host> <session>`で、`ghost-claude-reader`アカウントに正しく着地することの確認
- 案2（Windows OpenSSH経由、`wsl.exe -u ghost-codex-reader`）の実機動作確認 — `ghost-codex-reader`への切り替え後、まだ試していない
- Androidからの案3実接続、`codex resume --last`がリポジトリを読めて書けないことの実地確認

## 5. 今後の課題（優先度低・急ぎではない）

- `ghost-claude-writer` / `ghost-codex-writer`（developer同等の書き込み権限を持つ信頼済みアカウント）の設計・実装
- ネットワーク出口制限（今回のACL方式はファイルシステムの読み取り専用化のみで、ネットワークアクセス自体は制限していない）
- キーバインディングの不一致（submit-key/exit-key）— 優先度最低とすることで合意済み、対応は未着手

参照: `docs/designs/ghost_implementation_plan_ja.md`, `docs/designs/codex_implementation_plan_ja.md`, `docs/designs/side_effect_prohibit_ja.md`
