# Ghost Client からの副作用リクエストの禁止

## 背景

`docs/todos/2026-08-11.md` に追加された懸案:

> - Ghost クライアント側端末からのリクエストのうち副作用のあるものは絶対拒否

## 問題

`ghost join` は現状 `ssh -t ... tmux attach -t <session>` であり、Ghost Client
はオーナーと対等に同じ tmux セッションへ生の PTY として接続する（`bin/ghost-join`,
`bin/ghost-publish` 参照）。

この方式では、共有 PTY の中でどのキー入力がオーナー由来でどれが Ghost Client
由来かをプロトコル上区別する手段が無い。したがって、「副作用のあるリクエストだけ
事後的に拒否する」というフィルタは、今のセッション共有方式の上には作れない。

## 提案：ゲスト用に別セッションを立てる

副作用を止めたいなら、同じセッションを共有させないのが筋が良い。

- 同じワークスペース（ファイル・Git 履歴などの知識空間）は共有する
- ただし Ghost Client（オーナー本人以外）が `ghost join` した場合は、
  オーナー用セッションとは別の、権限を制限した専用セッションへ繋ぐ
- 制限は Claude Code 自身が持つ機構で実現できる（例: `--permission-mode plan`、
  `--disallowedTools Edit,Write,Bash` など）

これは記事本文（`note/0_prologue/article_ja.md`）で出てきた「所有者と外部質問者の
分離」「GhostNet Global（知識空間を共有しつつ、質問者ごとに推論セッションを分離する）」
という以前からの構想と同じ方向性。

### トレードオフ

今の `ghost publish <session名>` / `ghost join <host> <session名>` は、
「オーナーもゲストも同一セッションに同一権限で attach する」という対称設計で
完結している。この提案を実現するには、

- `<session名>` ごとに「オーナー用セッション」と「ゲスト用セッション」を
  複数束ねて管理する仕組み
- どの Ghost Client がどのゲスト用セッションに対応するか、という対応付け

をプロトコルに新たに持たせる必要がある。

## 実現方式：専用デーモンではなく遅延生成

Ghost Server は専用の常駐プロセス（デーモン）である必要はない。

- 常時 listen する部分は OS 標準の `sshd` にすでに乗っている
- ゲスト用セッションは、そのゲストが最初に `ghost join` してきた時点で
  遅延生成すればよい。これは `bin/ghost-publish` がすでに
  `tmux has-session` を見て無ければ作る、というパターンと同じ
- 2 回目以降の join は既存のゲスト用セッションに attach するだけ
- 使われていない間は、ただの空き tmux セッションとして安く放置できる

### Apache の prefork/worker MPM との類比

- `sshd`（常時 listen するマスタープロセス） = Apache のマスタープロセス
- ゲストごとに要求時生成・再利用される tmux + `claude` セッション = Apache の
  ワーカープロセス

## 未解決事項：セッションの reaping（回収）ポリシー

Apache でいう `MaxSpareServers` / `MaxConnectionsPerChild` に相当する、
「使われなくなったゲスト用セッションをいつ・どう畳むか」というポリシーが
別途必要になる。

現状の `ghost-publish` にはこの概念が無く、セッションはユーザーが手動で
`tmux kill-session` するまで残り続ける前提になっている。ゲスト用セッションを
増やす場合はここも設計に含める価値がある。

具体的な reaping 条件（アイドル時間の閾値、最大セッション数など）は
未決定。設計者への確認が必要。

## 未実装

本ドキュメントは設計メモであり、`bin/ghost-publish` / `bin/ghost-join` の
実装はまだこの非対称セッション方式に対応していない。
