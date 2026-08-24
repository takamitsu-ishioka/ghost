# Codex: 読み取り専用ユーザーによる副作用禁止 — 実装計画

## 背景

`codex/`は、Codex CLIセッションをAndroidからLAN経由で遠隔操作する仕組み（Android → WSL2/Windows → tmux → `codex`）で、[Claude/Ghost側](ghost_implementation_plan_ja.md)と並行して育ってきた別リポジトリ内ディレクトリ。今回、次の2点を優先順位として明示的に指示された:

1. **キーバインディングの不一致問題**（submit-key: Enter vs Alt+Enter/Shift+Enter、exit-key: ツールによってCtrl+Dの回数が違う）は優先度最低に変更。今回は対応しない。
2. **副作用禁止の問題**は、読み取り専用ユーザーで解決する。Claude/Ghost側で当初検討していたchroot方式（[ghost_implementation_plan_ja.md](ghost_implementation_plan_ja.md)参照、後に破棄）よりも意図的に単純な方式。

`codex`は現状`developer`（owner本人）としてそのまま動いており、隔離が一切ない — リポジトリへのフル書き込み、`git commit`/`push`、何でもできる。修正方針は、chrootもコマンド分類も使わず、標準的なPOSIXファイル権限とACLだけで「developerのホームの外には一切書き込めない」専用アカウントとして動かすこと。

## 実機で確認した事実（読み取り専用チェック、実装前に実施）

- `/home/developer`は`750 developer:developer`— group/otherはゼロアクセス（走査すら不可）。新しいユーザーは何も持たないところからスタートする。
- `~/.ssh`（`700`）、`~/.claude`（`700`、`.credentials.json`は`600`）、リポジトリ内に`.env*`は一切存在しない — developerのホームへの走査専用の付与と、リポジトリ本体への再帰的な読み取り専用ACL付与を組み合わせても、これらには一切到達できないことを確認済み。
- リポジトリ内に世界/グループ書き込み可能なファイルが4件存在していた（`docs/_CLAUDE.en.md` 777、`docs/_CLAUDE.md` 777、`note/0_prologue/article_ja.md` 777、`docs/designs/ghost_smartphone_application.ja.md` 666、いずれも`developer:developer`）。誰が読み取り専用ユーザーになろうと関係なく既に穴だったので、Codex対応とは無関係な前提修正として644へ修正済み。
- `setfacl`/`getfacl`（`acl`パッケージ）は未導入だった → 導入済み。
- `/etc/ssh/sshd_config`・`sshd_config.d/*`のどこにも`AllowUsers`/`DenyUsers`は無かった → 新規アカウントは`authorized_keys`を置くだけで標準ポートでSSH可能（案3の専用ポート2222のドロップインだけは別途アカウント名の付け替えが必要）。
- `developer`は元々パスワード無しの無制限sudo（`(ALL) NOPASSWD: ALL`）を持っている → `codex_remote_publish.sh`等をreaderアカウントとして動かすための新しいsudoersルールは不要。

## 命名

- `ghost-codex-reader` — 今回構築。
- `ghost-claude-reader` — Claude/Ghost側で並行構築（同じ機構、別アカウント）。
- `ghost-codex-writer` — 名前だけ予約。developerと同等の権限を持つ信頼済みアカウント。将来実装。

ツールごとにアカウントを分ける理由は[ghost_implementation_plan_ja.md](ghost_implementation_plan_ja.md)と共通（Yama LSM不在によるptrace/kill越境の懸念）なので、そちらを参照。

## 共有される機構（実装・検証済み）

`bin/ghost_reader_user_setup.sh <username> [--dry-run]`（Claude/Ghost側と共有、`codex/`に専用スクリプトは作らない）:

1. `acl`パッケージを未導入なら導入
2. `adduser --system --group --home /home/<username> --shell /bin/bash --disabled-password <username>` — 自前のグループ・書き込み可能なホーム（Codex自身のログイン状態・設定の置き場所）、`developer`グループにもsudoにも入れない
3. `setfacl -m u:<username>:--x`をdeveloperのホームへ（走査のみ）、`setfacl -R -m u:<username>:rX`と`setfacl -R -d -m u:<username>:rX`（デフォルトACLで将来のファイルにも自動継承）をリポジトリへ
4. `git config --global --add safe.directory <repo>` — gitの「dubious ownership」防止機構は、所有者の違うリポジトリでの`git status`のような読み取りコマンドまでブロックしてしまうため、reader専用の`.gitconfig`に明示的な例外を登録する（実機テストで発見した必須ステップ）

`ghost-codex-reader`で実行・検証済み: `git status`成功、`touch`失敗、`git commit`失敗（`.git`書き込み拒否）、`.ssh`/`.claude`読み取り失敗、再実行しても全項目「already」（冪等性確認）、`ghost-claude-reader`のプロセスに対する`kill -0`が`Operation not permitted`（UIDが別なのでクロスアカウントの干渉ができないことを確認）。

## `codex/`側への変更（実装済み）

- **`codex/bin/direct_wsl_server_setup.sh`**（案3・WSL直結）: `$HOME/.ssh/authorized_keys`・`AllowUsers $(id -un)`という「呼び出し元ユーザー」前提だった箇所を、`/home/ghost-codex-reader/.ssh/authorized_keys`・`AllowUsers ghost-codex-reader`に変更。鍵ファイルの読み書きは`sudo -u ghost-codex-reader`経由に変更（developerからは直接触れない別ユーザーのホームのため）。事前に`ghost-codex-reader`アカウントが存在することをチェックし、無ければ`bin/ghost_reader_user_setup.sh`実行を促すエラーを出す。
- **`codex/android/android_client_setup.sh`**（案2・Windows経由`wsl.exe -u <wsl_user>`）と**`android_direct_client_setup.sh`**（案3）: どちらも対象Linuxユーザーを引数として既に受け取る設計だったため、コード変更は不要。README側の実行例を`ghost-codex-reader`に更新。
- **`codex/README.ja.md`**: 手順の先頭に「0. 読み取り専用ユーザーを作る」を追加。案2の実行例の`<wsl_user>`引数を`developer`から`ghost-codex-reader`に変更。「既知の課題（優先度順）」節を新設し、副作用禁止（対応済み）とキーバインディング不一致（優先度: 低、未対応）を明示。
- **`codex/README.direct-wsl.ja.md`**: 同様に手順0を追加し、「自動化するもの」の説明を`ghost-codex-reader`の`authorized_keys`/`AllowUsers`に更新、案3の実行例の`<wsl_user>`引数を`ghost-codex-reader`に変更。
- **`codex/tests/test_scripts.sh`**: `bin/ghost_reader_user_setup.sh ghost-codex-reader --dry-run`の構文・dry-runチェックを追加し、既存のdry-runテストで使っていた`developer`プレースホルダーを`ghost-codex-reader`に更新。全テスト通過を確認済み。

## Codex CLI自身の資格情報

`ghost-codex-reader`自身のホーム（`/home/ghost-codex-reader`）は自分自身が書き込み可能なので、`sudo -u ghost-codex-reader codex login`（またはCodex CLIの認証フローに相当するもの）をowner本人が一度対話的に実行し、設定をそこに保存する想定。この手順はowner本人の対話操作が必要なため、私が代行することはできない。

## 未着手・今後の課題

- `direct_wsl_server_setup.sh`の実際の（`--dry-run`なしの）実行 — 新しいTCPポート2222をLANに公開する変更であり、README自身が定めている「Windows側のmirrored networking設定」「モバイル回線から到達できないことの確認」等の半自動・手動ステップと一体で進めるべきものなので、今回は準備（dry-runでの動作確認）のみに留め、owner自身の判断で実行してもらう。
- `ghost-codex-reader`としての`codex login`（owner本人が対話的に実行）
- `ghost-codex-writer`の設計・実装
- 案2（Windows OpenSSH経由）の実機での動作確認（`ghost-codex-reader`への切り替え後、まだ実機テストしていない）

## 検証

- `find <repo> \( -perm -0020 -o -perm -0002 \) -not -type l` — クリーン
- 上記「共有される機構」節の battery を`ghost-codex-reader`に対して実行済み
- `codex/tests/test_scripts.sh` — 全テスト通過済み
- 未実施: Androidからの実機接続（`ghost_codex_direct`）、`codex resume --last`がリポジトリを読めて書けないことの実地確認
