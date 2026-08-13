# Ghost: 公開セッションからのOS層での能力剥奪 — 実装計画

## 背景

`docs/designs/side_effect_prohibit_ja.md` は「Ghost クライアント側端末からのリクエストのうち副作用のあるものは絶対拒否」という todo 項目から出発し、批判的検討（同文書 21節以降、「Ghost セキュリティ設計書」）を経て、具体的なアーキテクチャに到達し、最後に Claude Code（私）宛の明示的な実装依頼（18節）で締めくくられている。同文書が求める中核不変条件（16節）は次の通り:

> Ghost 公開セッション内で動く任意のプロセスが、Claude の判断内容に関係なく、Ghost Server Owner の保護対象状態を変更できないこと。

現状の実装はこの性質を一切持たない。`ghost-publish` は `tmux` + `claude` を隔離なしに呼び出し元（owner）ユーザーとしてそのまま起動しており、`ghost-trust` はゲストの SSH 公開鍵を**呼び出し元ユーザー自身**の `authorized_keys` に追加している — つまり「信頼された」ゲストは制限されたビューではなく、owner の実際の Linux アカウントへの本物のログインシェルを得てしまう。`ghost-join` も単なる `ssh -t host tmux attach -t session` であり、owner とゲストが1本の生PTYを共有し誰が何を入力したか区別できない — まさに設計書2節が指摘する問題そのものである。

設計書の答えは、Claude の判断の上に権限分類レイヤーを重ねることではなく、公開セッションが動くOS環境そのものから副作用を起こす**能力**を除去すること（専用Unixユーザー、chroot、資格情報の不可視化、ネットワーク出口制限）にある。プロンプトも、誤判断も、注入された指示も、そもそも関係なくなるようにする。

本計画は、この設計を現在の `bin/ghost-*` スクリプト群に対する具体的なフェーズへ落とし込む。このマシンで実際に使えるもの（直接確認済み、後述）だけを前提とし、入っていないツールの存在を仮定しない。

## 環境調査結果（方針の根拠）

このマシン（Ubuntu 24.04, WSL2, `developer` はパスワードなし sudo 可）で直接確認した内容:

- `docker`/`podman` なし、`debootstrap` なし。`chroot(1)` は存在する。
- 非特権 `unshare`（mount/net/pid namespace）は "Operation not permitted" で失敗する。同じコマンドは `sudo` 下では成功する。つまり namespace ベースの隔離は root 起点でなければならず、`ghost` ユーザー自身が自分で行うことはできない。
- `iptables`/`nftables` は未インストール（`ghost-initialize` が tmux/sshd/avahi に対して既に行っているのと同様、apt で導入可能）。
- `claude` バイナリ本体（`~/.local/share/claude/versions/2.1.228`）は単一の自己完結型 ELF で、動的リンク先はごく普通のライブラリ6個のみ（libc, libm, libdl, libpthread, librt, ld-linux）— node_modules のような広がりはない。`tmux` や基本的な読み取り系ツール（`cat`, `grep`, `sed`, `awk`, `find`）も同様に、`ldd` で解決できる小さな依存関係の閉包を持つ。

結論: **厳選した最小 chroot**（許可リストに載ったバイナリとその共有ライブラリ閉包だけをコピーする）は、このマシンでは構築コストが低く、設計書自身の「能力剥奪であって禁止リストではない」という原則（2.3節）にも合致する — host の実 `/usr` をそのままバインドマウントしてしまうと、誰も直接呼ばなくても `git`/`curl`/`python` が手の届く場所に戻ってきてしまい、趣旨に反する。Docker は v1 では見送り（未インストールであり、設計書自身も「最小構成を試す前に重量級フレームワークに飛びつくな」と述べている）。ネットワーク出口については、`iptables -m owner --uid-owner ghost` の方が完全な network namespace + veth 構成より単純で、「`ghost` の UID が到達できる範囲を制限する」という意図をそのまま表現できる（namespace 内で DNS/NAT を再構築する必要がない）。

## Phase 6 の資格情報方式（決定済み）

当初「専用の低権限APIキー」と「既存OAuthセッションの再利用」の二択として検討していたが、検討の結果、前者は実質的に選択肢として存在しないことが判明した。Claude Pro/Max サブスクリプションは claude.ai（および OAuth 経由で使う Claude Code のような一部ファーストパーティ製品）向けの契約であり、Anthropic API（console.anthropic.com で発行する API キー、従量課金）とは別建てである。Pro/Max の契約からは API キーを発行できず、発行するには別途 API アカウントを新規作成し、別のクレジットカードで課金設定する必要がある。

採用する方式: **`ghost` Unix ユーザー専用に、同じ Pro/Max アカウントで別の OAuth ログインセッションを張る**（`sudo -u ghost claude login` 相当）。

- 契約・課金には手を付けない
- 資格情報ファイルは `ghost` のホーム（`~/.claude/.credentials.json` 相当）に物理的に分離される — owner側のファイルとは別物なので、chroot 越しに見える範囲を絞る Phase 4 の方針と両立する
- 「低権限」ではなく同一アカウントだが、セッション自体は独立しているため、万一漏洩しても claude.ai のアカウント設定からそのセッションだけを個別に失効でき、owner の普段使いセッションは無傷のまま維持できる

この決定により、Phase 6 は他のフェーズ（1–5, 7–8）と同様に着手可能であり、もはやブロッカーではない。

## フェーズ別実装計画

**Phase 1 — `ghost` Unixユーザー + ディレクトリ雛形**
専用システムユーザー `ghost`（パスワードなし、最小シェル）と `/var/lib/ghost/{root,tmp,knowledge}` を作成する。`bin/ghost-initialize` が既に持っている冪等な「already / missing」パターン（パッケージ、PATH、SSH鍵ペアに対して既に実施済み）を拡張する形で行い、新しい仕組みは発明しない。低リスクで完全に可逆（ユーザーと空ディレクトリの追加のみ）。

**Phase 2 — 最小chroot rootfsビルダー**
新規 `bin/ghost-chroot-build`（薄いbashラッパー、リポジトリの規約通り）+ `bin/ghost_chroot_build.py`（非実行 — 依存閉包の解決ロジックは複雑なのでPython側に置き、ラッパーから呼ぶ。`tools/document_translate.sh`/`.py` と同じ分割パターン）。
- 許可リストは `cat`, `grep`, `sed`, `awk`, `find`（6節が挙げる例そのもの）に加え、`claude` と `tmux`（設計書4節のアーキテクチャ上、境界の内側で必須）。
- それぞれについて `ldd` で共有ライブラリ閉包を解決し、バイナリ・ライブラリ・動的リンカを `/var/lib/ghost/root/{bin,lib,lib64,usr/lib/x86_64-linux-gnu}` へパスを保持したままコピーする。
- 最小限の `/etc/passwd`, `/etc/group`, `/etc/nsswitch.conf`、および `/dev/{null,zero,urandom,tty}` デバイスノード — バイナリが動くのに最低限必要な分だけ。`/proc`/`/sys` は明示的にマウントしない（14節自身の警告）。何かが実際に必要とすることが分かるまでは。
- `--dry-run` は何も書き込む前に、解決されたバイナリ・ライブラリ閉包とコピー先パスを表示する（副作用のあるスクリプトに関するリポジトリ規約に合わせる）。

**Phase 3 — `ghost` ユーザー向けsshd配線**
- 新規 `/etc/ssh/sshd_config.d/ghost.conf` ドロップイン（Ubuntu規約 — 本体の `sshd_config` は直接編集しない）。`Match User ghost` ブロックで `ChrootDirectory /var/lib/ghost/root`、`$SSH_ORIGINAL_COMMAND` を読み取り現在公開中のセッション名と照合してから（クライアント指定コマンドをそのまま実行するのではなく）`tmux attach -t <session>` をexecするchroot内ディスパッチャへの `ForceCommand`、加えて `AllowTcpForwarding no`, `X11Forwarding no`, `AllowAgentForwarding no`。
- `bin/ghost-trust` は、ゲストの鍵を呼び出し元ユーザーではなく `ghost` ユーザーの `authorized_keys` に追加するよう変更する — これにより「ゲストがownerとして本物のログインを得てしまう」穴を直接塞ぐ。
- このフェーズは稼働中のsshd設定を変更する — ユーザーとチェックポイントを取り、reload前に `sshd -t` で検証する。

**Phase 4 — knowledgeビュー + 資格情報の不可視化**
明示的で狭い許可リスト（このリポジトリ内の非秘密パスのみ — マウント前にユーザーと範囲を確認）を `/var/lib/ghost/root/knowledge` へ読み取り専用バインドマウントする。7節の禁止リスト（SSH秘密鍵、GitHub/クラウド資格情報、`.env` シークレット、ブラウザプロファイル、GPG鍵、OAuthトークン、owner のホームディレクトリ全体）がchroot内から一切到達不能であることを明示的に検証する。

**Phase 5 — `ghost-publish` のセッション所有者変更**
`ghost-publish` が起動する tmux セッションと `claude` プロセスを、範囲を絞ったsudoersルール（一般的なsudo権限ではない）経由で `ghost` ユーザーとして実行するよう変更する。owner自身のローカルアタッチも、素の `tmux attach` ではなく `sudo -u ghost tmux attach -t <session>` になる。これにより、`ghost publish` を実行した瞬間、owner もゲストと**同じ制限区域**に参加することになる — 「誰がアタッチしているかで分類しない」という2.1節の方針と一致する。制限なしのClaude Codeを使いたいownerは、Ghostとは無関係に素の `claude` を実行すればよい。CLI表面（`ghost publish <name>`, `ghost join <host> <name>`）は変更しない（18節項目10）。

**Phase 6 — Claude資格情報 + ポリシープロンプト**
上記で決定した方式（`ghost` ユーザー専用のOAuthセッション）を配線する。10節のようなロール・ポリシーテキストは、既存のstdin契約（`echo "policy text" | ghost-publish ...`）経由でセッションに渡す — 新しいフラグは不要。

**Phase 7 — ネットワーク出口制限**
`bin/ghost-initialize` のパッケージリストに `iptables` を追加する。uid `ghost` からの outbound を、`claude` が実際に必要とするAnthropic APIエンドポイント以外はデフォルト拒否にする。許可した宛先を、9節が明示的に求める脅威モデルのメモとして書き残す。

**Phase 8 — テストスイート**
新規 `tests/ghost_security_test.sh`（リポジトリにはまだテスト基盤がない）を、ローカルに公開されたGhostセッションに対して通常アカウントから実行し、設計書自身のチェックリストをそのままカバーする:
- 失敗すべきもの: owner の保護対象ファイルの変更・削除、`git commit`/`push`、SSH秘密鍵の読み取り、認証済み外部サービスへの書き込み、権限昇格（`sudo`/`su`）、通常の経路でのchroot外への到達。
- 引き続き動作すべきもの: 許可リストに載ったknowledgeの読み取り、検索、分析、質問への回答、ローカルjoin、リモートSSH join、2つの端末が1つのClaudeセッションを共有すること。

## 変更対象ファイル（代表例）

- `bin/ghost-initialize` — ghostユーザー + iptables導入を、既存の冪等パターンのまま拡張。
- `bin/ghost-publish` — セッションを `ghost` として実行するよう変更。
- `bin/ghost-trust` — `ghost` の `authorized_keys` を対象にするよう変更。
- `bin/ghost-join` — おそらく変更なし。ForceCommandディスパッチャができた時点で確認。
- 新規 `bin/ghost-chroot-build` + `bin/ghost_chroot_build.py`。
- 新規 `/etc/ssh/sshd_config.d/ghost.conf`（リポジトリ外のシステムファイル。`docs/designs/` に記録する）。
- 新規 `tests/ghost_security_test.sh`。
- `docs/designs/side_effect_prohibit_ja.md` — フェーズが実装されるごとに実装ログを追記する。現在空（0バイト）のままの `side_effect_prohibit_en.md` は、ja文書が安定した時点で `tools/document_translate.sh` により再生成する。

## 実行上の注意

- Phase 1–2 は低リスク・可逆（新規ユーザー、新規ディレクトリ、まだ配線されていないchrootへのファイルコピー）であり、承認され次第着手できる。
- Phase 3 は稼働中のsshd設定に触れる — reload前に明示的なチェックポイントを置き、まず `sshd -t` で構文チェックする。
- Phase 5 は `ghost-publish` の実行主体を変更する — 今日時点の挙動を変えるため、切り替え前にチェックポイントを置く。
- Phase 6 はブロッカーが解消されたため、他フェーズと同様に進行可能。

## 検証

- Phase 2完了後の手動スモークテスト: sshdが配線される前に `sudo chroot /var/lib/ghost/root /bin/cat --version` 相当を実行する。
- Phase 3の設定ドロップイン追加後、reload前に `sshd -t`。
- Phase 8完了後の `tests/ghost_security_test.sh` フルラン: 否定的ケースはすべてfail closed、肯定的ケースはすべて引き続き動作すること。
