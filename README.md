# Ghost

**本人がいなくても、ghostはいる。**

Ghost は、人・AI・知識・作業セッションを LAN 上でアドレス可能な「エージェント」として扱うための構想・実装リポジトリです。詳細な発想の経緯は [`idea.md`](./idea.md) を参照してください。

## 何のためのシステムか

Claude Code の UI は本質的に「stdin からキーイベントを受け取り、stdout に端末制御文字列（ANSI/VTエスケープ）を吐き続けるプログラム」です。この事実を起点に、次のように発展させます。

1. **PTY を延長する** — tmux + SSH で PTY をそのまま LAN 越しに運べば、Claude Code の対話 UI ごと別マシンから接続できる。
2. **知識空間に接続する** — `claude-join <person>` ではなく `claude-join <knowledge-space>`。persistent type の ghost なら、本人が休暇中・会議中・退職済みでも問い合わせ可能。
3. **AI 同士が取材する** — PM Agent が各メンバーの ghost を取材し、進捗・ブロッカーを人間の報告なしに集約する。

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

## 「本当にそんなことができるのか」への実例

構想だけでなく、実際に AI が記憶（過去の会話・決定）と実装（ファイル・git 状態という SSoT）を突き合わせて検証してから答えている例を `idea.md` 末尾に収録しています。

- 短期記憶と長期ルーティンの統合想起（`images/recall-schedule.png`）
- 記憶の再生ではなく grep・shell で再検証してから回答（`images/recall-investigation.png`）
- 会話履歴なしに git 履歴だけから設計意図・採用理由を再構成（`images/repo-design-intent.png`）

## 現在の状態

このリポジトリは現時点では構想メモ（`idea.md`）と実例画像（`images/`）のみで、`ghost` CLI 自体はまだ実装されていません。仕様書に記載なし・今後の実装予定です。
