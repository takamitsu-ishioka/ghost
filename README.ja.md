[English](./README.md) | 日本語

# Ghost

**本人がいなくても、ghostはいる。**

Ghost は、人・AI・知識・作業セッションを LAN 上でアドレス可能な「エージェント」として扱うための構想・実装リポジトリです。詳細な発想の経緯は [`idea.ja.md`](./idea.ja.md) を参照してください。

## 何のためのシステムか

Claude Code の UI は本質的に「stdin からキーイベントを受け取り、stdout に端末制御文字列（ANSI/VTエスケープ）を吐き続けるプログラム」です。この事実を起点に、次のように発展させます。

1. **PTY を延長する** — tmux + SSH で PTY をそのまま LAN 越しに運べば、Claude Code の対話 UI ごと別マシンから接続できる。

2. **知識空間に接続する**
      ```
      $ claude-join <ghost-knowledge-space-name>
      ```
      このコマンドで、
      - 特定リポジトリ
      - リポジトリの開発者とエージェントのセッションログ
      - 開発者の設計思想
      - 開発者の実装規則
      から成る「ghost (知識空間)」に接続する。
      ghost なら、本人が休暇中・会議中・退職済みでも問い合わせ可能。  

3. **AI 同士が取材する**  
   PM の状況把握は、PM のエージェントが各メンバーの ghost から取材し、進捗・ブロッカーを人間の報告なしに集約する。

これを一言で表す名前が **Ghost**（攻殻機動隊由来）です。

```text
ghost           システム全体
ghost ls        Ghostを探す
ghost join      Ghostに接続する
ghost publish   自分のGhostを公開
ghost ask       Ghostに問い合わせる
ghost interview Ghostを取材する
```

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

構想だけでなく、実際に AI が記憶（過去の会話・決定）と実装（ファイル・git 状態という SSoT）を突き合わせて検証してから答えている例を `idea.ja.md` 末尾に収録しています。

- 短期記憶と長期ルーティンの統合想起（`images/recall-schedule.png`）
- 記憶の再生ではなく grep・shell で再検証してから回答（`images/recall-investigation.png`）
- 会話履歴なしに git 履歴だけから設計意図・採用理由を再構成（`images/repo-design-intent.png`）

## CLAUDE.md（大前提・DJCの出典）

`idea.ja.md` 中の「大前提1」「大前提3 - DJC」等の注記は、このリポジトリ直下の [`CLAUDE.ja.md`](./CLAUDE.ja.md) にリンクしています。これは山田喜三郎のグローバル `~/.claude/CLAUDE.md` の実体コピーで、`_CLAUDE.md`（同ファイルへのシンボリックリンク、`.gitignore` 対象）から [`claude_md_sync.sh`](./claude_md_sync.sh) で同期しています。英語版正本 `CLAUDE.md` は同様に `~/.claude/CLAUDE.en.md`（`_CLAUDE.en.md`）から同期されます。git はシンボリックリンクをリンクのまま push してしまうため、リポジトリに含めて公開するのは同期後の実体です。

## 使い方

`ghost` CLI は [`bin/`](./bin) にあります。現時点では、構想の土台となる「tmux + SSH でLAN越しにClaude Codeのセッションを共有する」部分、すなわち2コマンドのみ実装しています。

```bash
# Claude Codeを実行する側のマシンで
$ bin/ghost publish work
# → tmux new-session -A -s work claude

# LAN内の別マシンから
$ bin/ghost join dev-yamada work
# → ssh -t dev-yamada tmux attach -t work
```

引数なしで `bin/ghost` を実行すると利用可能なサブコマンド一覧が表示されます。

## 現在の状態

`ghost publish` / `ghost join`（tmux + SSHによるPTY共有の土台）は実装済みです。`ghost ls`（LAN内発見）、`ghost ask` / `ghost interview`（persistent knowledge space）は未実装です。設計の議論は `idea.ja.md` / `idea.md` を参照してください。
