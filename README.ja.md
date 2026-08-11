[English](./README.md) | 日本語

<img width="1732" height="908" alt="0_prologue_title_ja" src="https://github.com/user-attachments/assets/5e7ad5c1-5932-4616-8b9f-9a7a49fc981c" />

# Ghost

**本人がいなくても、ghostはいる。**

Ghost は、人・AI・知識・作業セッションを LAN 上でアドレス可能な「エージェント」として扱うための構想・実装リポジトリです。詳細な発想の経緯は [`docs/idea.ja.md`](./docs/idea.ja.md) を参照してください。

## 何のためのシステムか

Claude Code の UI は本質的に「stdin からキーイベントを受け取り、stdout に端末制御文字列（ANSI/VTエスケープ）を吐き続けるプログラム」です。この事実を起点に、次のように発展させます。

1. **PTY を延長する** — tmux + SSH で PTY をそのまま LAN 越しに運べば、Claude Code の対話 UI ごと別マシンから接続できる。

2. **知識空間に接続する**
      ```
      $ ghost join <server-host> <session-name>
      ```
      このコマンドで、
      - 特定リポジトリ
      - リポジトリの開発者とエージェントのセッションログ
      - 開発者の設計思想
      - 開発者の実装規則
      から成る「ghost (知識空間)」に接続する。  
      ghost なら、本人が休暇中・出張中・会議中・退職済みでも問い合わせ可能。  

3. **AI 同士が取材する**  
   例えばプロジェクト管理者が進捗状況を把握したい場合は、そのプロジェクト管理者のエージェントが各メンバーの ghost から取材し、進捗・ブロッカーを人間の報告なしに集約することができる。

これを一言で表す名前が **Ghost**（攻殻機動隊由来）です。

チェック付きは実装済みです:

- [x] `ghost` — システム全体
- [x] `ghost ls` — Ghostを探す
- [x] `ghost join` — Ghostに接続する
- [x] `ghost publish` — 自分のGhostを公開

複数の ghost が相互接続されるネットワークを **GhostNet** と呼びます。

```text
             GhostNet

      ┌── Hiratsuka Ghost
      │
PM Ghost ── Yamada Ghost
      │
      └── Suzuki Ghost
```

## 用語集

- **Ghost** — `ghost publish` で公開される知識・作業空間。`<host> <session_name>` でアドレス指定する。
- **Ghost Server** — `ghost publish` を実行するホスト（tmuxセッションを所有する側。joinにおけるSSHサーバー側）。
- **Ghost Client** — `ghost join <ghost server hostname> <ghost server session name>` を実行する側（joinにおけるSSHクライアント側）。
- **GhostNet** — publish/joinで相互接続された複数Ghostのネットワーク。

## 「本当にそんなことができるのか？」への回答

構想だけでなく、実際に AI が記憶（過去の会話・決定）と実装（ファイル・git 状態という SSoT）を突き合わせて検証してから答えている例を `docs/idea.ja.md` 末尾に収録しています。

- 短期記憶と長期ルーティンの統合想起（`docs/images/recall-schedule.png`）
- 記憶の再生ではなく grep・shell で再検証してから回答（`docs/images/recall-investigation.png`）
- 会話履歴なしに git 履歴だけから設計意図・採用理由を再構成（`docs/images/repo-design-intent.png`）

## CLAUDE.md（大前提・DJCの出典）

`docs/idea.ja.md` 中の「大前提1」「大前提3 - DJC」等の注記は、[`docs/CLAUDE.ja.md`](./docs/CLAUDE.ja.md) にリンクしています。これは山田喜三郎のグローバル `~/.claude/CLAUDE.md` の実体コピーで、`docs/_CLAUDE.md`（同ファイルへのシンボリックリンク、`.gitignore` 対象）から [`tools/claude_md_sync.sh`](./tools/claude_md_sync.sh) で同期しています。英語版正本 `docs/CLAUDE.md` は同様に `~/.claude/CLAUDE.en.md`（`docs/_CLAUDE.en.md`）から同期されます。git はシンボリックリンクをリンクのまま push してしまうため、リポジトリに含めて公開するのは同期後の実体です。

## 使い方

`ghost` CLI は [`bin/`](./bin) にあります。マシンごとに一度 `bin/ghost-initialize` を実行すると、必要なaptパッケージのインストール、`bin/` の `PATH` 追加、`ghost join` をパスワード無しで使うための専用鍵 `~/.ssh/id_ed25519_ghost` の生成まで行われます。

GhostNetには中央の登録先が無いので、Ghost Server側の管理者にjoinする側の公開鍵をチャットやメール等で送り、登録してもらう必要があります。

```bash
# Ghost Client（join する側）で、ghost-initialize後
$ cat ~/.ssh/id_ed25519_ghost.pub
# → この1行をGhost Serverの管理者に送る

# Ghost Server側で、鍵を受け取ったら
$ echo '<受け取った公開鍵の1行>' | ghost trust yamada
# → ~/.ssh/authorized_keys に追加（登録済みならスキップ）
```

そのうえで、tmux + SSH でLAN越しにClaude Codeのセッションを共有します。`ghost publish` はセッションをmDNS（`_ghost._tcp`）でLANにも広告し、この広告はtmuxセッション自体のライフタイムに紐付いているため、セッションを終了すると自動的に消えます。

```bash
# Ghost Server（Claude Codeを実行する側のマシン）で
$ ghost publish work
# → tmuxセッション"work"を作成（または既存にアタッチ）してclaudeを実行し、
#   _ghost._tcp としてLANに広告する

# "--" の後ろはそのまま claude へスルーパスされる
$ ghost publish work -- --dangerously-skip-permissions

# LAN内の別マシンから、公開されているものを探す
$ ghost ls
SESSION                  HOST
work                     dev-yamada.local

# Ghost Client側で、登録が済んでいれば
$ ghost join dev-yamada.local work
# → ssh -i ~/.ssh/id_ed25519_ghost -t dev-yamada.local tmux attach -t work
```

引数なしで `ghost` を実行すると利用可能なサブコマンド一覧が表示されます。

## 懸案事項

基本原則: Ghost Clientがキーを押したときの**意図**と、Ghost Serverの**実際の挙動**が一致すること。以下の2点は未解決です。

- **送信キーの不一致**: Claude Codeのデフォルトの送信キーはEnterですが、*Ghost Server*側の `~/.tmux.conf` に
  ```
  set -s extended-keys on
  set -as terminal-features 'xterm*:extkeys'
  ```
  が無いと、tmuxがEnterと修飾付きEnter（Alt+Enter、Shift+Enter）を同じバイト列に潰してしまい、Ghost Clientの「Enterを押した＝送信のつもり」という意図が共有中の`claude`プロセスに正しく伝わらないことがあります。これはサーバー側のtmux設定であり、クライアント側だけでは直せません。
- **終了キーの不一致**: `ghost join` は現時点で、セッション内で実際に何が動いているか（例: `claude`はCtrl+D二回、`codex`はCtrl+D一回で終了）をGhost Clientに伝える手段がありません。`ghost publish` はまだ起動したコマンドを記録・広告していないため、どこにも表示されません。

## 現在の状態

`ghost initialize`、`ghost trust`、`ghost publish`、`ghost join`、`ghost ls`（セットアップ、tmux + SSHによるPTY共有の土台、mDNSによるLAN内発見）は実装済みです。設計の議論は `docs/idea.ja.md` / `docs/idea.md` を参照してください。
