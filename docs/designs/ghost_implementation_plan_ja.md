# Ghost: 公開セッションの読み取り専用化 — 実装計画

## 背景

`docs/designs/side_effect_prohibit_ja.md` は「Ghost クライアント側端末からのリクエストのうち副作用のあるものは絶対拒否」という todo 項目から出発し、批判的検討（同文書 21節以降、「Ghost セキュリティ設計書」）を経て具体的なアーキテクチャに到達した。同文書が求める中核不変条件（16節）は次の通り:

> Ghost 公開セッション内で動く任意のプロセスが、Claude の判断内容に関係なく、Ghost Server Owner の保護対象状態を変更できないこと。

現状の実装はこの性質を一切持たない。`ghost-publish` は `tmux` + `claude` を隔離なしに呼び出し元（owner）ユーザーとしてそのまま起動しており、`ghost-trust` はゲストの SSH 公開鍵を**呼び出し元ユーザー自身**の `authorized_keys` に追加している — つまり「信頼された」ゲストは制限されたビューではなく、owner の実際の Linux アカウントへの本物のログインシェルを得てしまう。`ghost-join` も単なる `ssh -t host tmux attach -t session` であり、owner とゲストが1本の生PTYを共有し誰が何を入力したか区別できない — まさに設計書2節が指摘する問題そのものである。

## 方針転換: chrootをやめ、読み取り専用ユーザー + ACLへ

当初、専用Unixユーザー・chroot・資格情報の不可視化・ネットワーク出口制限を組み合わせた「最小chroot」案（`bin/ghost-chroot-build`、`ChrootDirectory`+`ForceCommand`のsshd設定、bind mountされたknowledgeビュー、iptablesによるegress制限）を検討・詳細設計した。

その後、並行して進めていた Codex 版（`codex/`、[docs/designs/codex_implementation_plan_ja.md](codex_implementation_plan_ja.md)）で、より単純な代替案 — **chrootを使わず、標準的なUnixファイル権限とPOSIX ACLだけで同じ不変条件を満たす** — を先に実装・検証した。この方式は:

- developerのホーム（`750`、group/otherはゼロアクセス）に対する走査のみのACL付与と、リポジトリ本体に対する再帰的な読み取り専用ACL付与だけで完結する
- `~/.ssh`（`700`）、`~/.claude`（`700`、`.credentials.json`は`600`）等の機密ディレクトリは、親ディレクトリの走査権限だけでは一切露出しないことを実機で確認済み
- `git commit`/`push`は`.git`への書き込みが拒否されるため自然に失敗する — コマンド分類は不要
- chroot・namespace・iptablesより検証済みで、実装量が桁違いに小さい

実機での確認・検証を経て、こちらの方式に一本化する（chroot案は破棄）。設計書自身の「最小構成を優先する」原則（同文書652行付近）にも、「能力を分類するのではなく、そもそも持たせない」という2.2〜2.3節の原則にも、より忠実な帰結だと判断した。

## 命名規約

ユーザーとの2度の擦り合わせを経て、次のアカウント名に確定した:

- `ghost-claude-reader` — 今回構築する。Claude Code用の読み取り専用アカウント。
- `ghost-codex-reader` — 今回構築する。Codex用の読み取り専用アカウント（[codex_implementation_plan_ja.md](codex_implementation_plan_ja.md)参照）。
- `ghost-claude-writer` / `ghost-codex-writer` — **名前だけ予約**。将来、developerと同等の権限を持つ信頼済み協力者用アカウントを登録する際に使う。今回は実装しない。

**ツールごとにアカウントを分ける理由**: このマシンには `/proc/sys/kernel/yama/ptrace_scope` が存在しない（WSL2カーネルにYama LSMが無い）ため、Unixの古典的な規則がそのまま適用される — 同一UIDのプロセス同士は`kill`/`ptrace`し合える。ClaudeセッションとCodexセッションを同じアカウントで動かすと、一方の暴走・侵害がもう一方に干渉できてしまう。developerのファイルに触れないことは保証できても、セッション同士の分離は保証できない。アカウントを分けることで、この分離を維持しつつ機構は共有する。

## 共有される機構

`bin/ghost_reader_user_setup.sh <username> [--dry-run]` が両アカウントに共通のロジックを一本化している（Codex版の`codex_user_setup.sh`という別スクリプトは作らず、これを両方から呼ぶ）:

1. `acl`パッケージ（`setfacl`/`getfacl`）を未導入なら導入
2. システムユーザーを未作成なら作成: `adduser --system --group --home /home/<username> --shell /bin/bash --disabled-password <username>` — 自前のグループ、自前の書き込み可能なホーム（そのツール自身の資格情報・設定の置き場所）、`developer`グループにもsudoにも入れない
3. ACLを未付与なら付与: `setfacl -m u:<username>:--x` をdeveloperのホームへ（走査のみ）、`setfacl -R -m u:<username>:rX` と `setfacl -R -d -m u:<username>:rX`（将来追加されるファイルにも自動継承させるデフォルトACL）をリポジトリへ
4. `git config --global --add safe.directory <repo>` をそのアカウントとして登録（gitの「dubious ownership」防止機構が、所有者の違うリポジトリでの読み取りコマンドまでブロックしてしまうため。実機テストで発見）

`--dry-run`は何も変更する前に、何を作成・付与するかを表示する。全ステップが冪等 — 既に完了している項目は「already」と報告してスキップする。

**実装・検証済み**: `bin/ghost_reader_user_setup.sh ghost-claude-reader` と `... ghost-codex-reader` を実行し、両アカウントを作成、ACL付与、safe.directory登録まで完了。以下を実機で確認:
- `sudo -u ghost-claude-reader git -C <repo> status` → 成功（読み取りできる）
- `sudo -u ghost-claude-reader touch <repo>/x` → 失敗（Permission denied）
- `sudo -u ghost-claude-reader git -C <repo> commit --allow-empty -m x` → 失敗（`.git/index.lock`への書き込み拒否）
- `sudo -u ghost-claude-reader cat ~developer/.ssh/authorized_keys` / `~developer/.claude/.credentials.json` → いずれも失敗
- 再実行しても全項目「already」と報告され、副作用なし（冪等性確認）
- `ghost-claude-reader`と`ghost-codex-reader`は異なるUID — 一方が起動したプロセスに対し、もう一方からの`kill -0`は`Operation not permitted`

## `bin/ghost-*` への変更（実装済み）

- **`bin/ghost-initialize`**: 既存の冪等な「already/missing」チェックリスト（パッケージ・PATH・SSH鍵）に、`bin/ghost_reader_user_setup.sh ghost-claude-reader`の呼び出しを追加。
- **`bin/ghost-trust`**: ゲストの公開鍵を、呼び出し元ユーザー自身の`authorized_keys`ではなく`/home/ghost-claude-reader/.ssh/authorized_keys`へ登録するよう変更。ファイル操作は`sudo -u ghost-claude-reader`経由で行い、所有権を正しく保つ。これが「信頼済みゲストがownerとして本物のログインを得てしまう」穴を実際に塞ぐ変更。
- **`bin/ghost-publish`**: tmuxセッションと`claude`プロセスを`sudo -u ghost-claude-reader tmux ...`経由で作成・実行するよう変更。owner自身のローカルアタッチも`sudo -u ghost-claude-reader tmux attach -t <session>`になる — `ghost publish`を実行した瞬間、ownerもゲストと同じ制限区域に入る（2.1節の「誰がアタッチしているかで分類しない」に一致）。制限なしのClaude Codeが欲しいownerは、Ghostとは無関係に素の`claude`を実行すればよい。session未作成時は`tmux new-session -d -c <repo_dir>`でカレントディレクトリをリポジトリに固定。
- **`bin/ghost-join`**: SSH接続先を`"$host"`から`"ghost-claude-reader@$host"`に変更。SSHクライアントの「ローカルユーザー名と同名で接続」というデフォルト挙動に依存せず、常にreaderアカウントへ明示的にランドするようにした。
- **廃止**（chroot案から不要になったもの）: `bin/ghost-chroot-build` / `bin/ghost_chroot_build.py`、`/etc/ssh/sshd_config.d/ghost.conf`の`ChrootDirectory`+`ForceCommand`ディスパッチャ、bind mountされたknowledgeビュー、iptablesによるegress制限フェーズ。制限はアカウント/ファイルシステムのレベルで実現されており、コマンドやネットワークのレベルでの分類は不要になった。

## Anthropic資格情報（Phase 6として検討・決定済み）

Claude Pro/Maxサブスクリプションからは、Anthropic API用のAPIキーを発行できない（別建ての契約・課金が必要）。よって「専用の低権限APIキー」という選択肢は実質存在しない。

採用する方式: `ghost-claude-reader`専用に、同じPro/Maxアカウントで別のOAuthログインセッションを張る（owner自身が`sudo -u ghost-claude-reader claude`を対話的に一度実行する）。資格情報は`/home/ghost-claude-reader`配下に物理的に分離され、万一漏洩してもclaude.aiのアカウント設定からそのセッションだけを個別に失効できる。この手順はowner本人による対話的なログインが必要なため、私が代行することはできない — 準備はここまで済ませてある。

## 未着手・今後の課題

- `ghost-claude-reader`としての`claude login`（owner本人が対話的に実行）
- ネットワーク出口制限（chroot案のPhase 7相当）は、実装量とのバランスを見て別途要検討 — 今回のACLベースの方式はファイルシステムの読み取り専用化のみが目的で、ネットワークアクセス自体は制限していない
- `ghost-claude-writer` / `ghost-codex-writer`（developerと同等の書き込み権限を持つ信頼済みアカウント）の設計・実装
- `docs/designs/side_effect_prohibit_ja.md`への実装ログ追記（chrootを検討→破棄した経緯を含む）
- 現在0バイトのままの`docs/designs/side_effect_prohibit_en.md`を、ja文書が安定した時点で`tools/document_translate.sh`により再生成

## 検証

- `find <repo> \( -perm -0020 -o -perm -0002 \) -not -type l` — リポジトリ内に世界/グループ書き込み可能なファイルが無いこと（実装時に発見した4件の穴は既に644へ修正済み）
- 上記「実装・検証済み」の battery を両アカウントに対して実行
- `ghost publish` → owner自身のローカルアタッチが`ghost-claude-reader`に着地すること
- `ghost trust` → 別マシンの`ghost join`が同じアカウント・同じtmuxセッションに着地すること（実機の別マシンでの確認は未実施）
