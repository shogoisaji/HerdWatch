# HerdWatch

herdr 上で並走する AI コーディングエージェントの状態を、ピクセルアートの家畜キャラクターとして専用ウィンドウに常時可視化する macOS アプリ。「どの pane が完了したか・どれを見るべきか」を一瞥で判断し、キャラをタップして該当 pane へ即ジャンプするために存在する。

状態の真実源は herdr であり、HerdWatch は独自の未読管理・永続化を持たない（→ [ADR-0001](docs/adr/0001-herdr-as-single-source-of-truth.md)）。そのため、アプリが正しく動くには **herdr 側のセットアップ** が前提になる。

> 用語・設計判断の正本は [CONTEXT.md](CONTEXT.md) と [docs/adr/](docs/adr/)。

## 必要環境

- macOS 26.0 以降（非サンドボックス）
- [herdr](https://herdr.dev/) がインストール済みで、サーバーが起動していること
- iOS Companion（`HerdWatchIOS`）を使う場合は iOS 26.0 以降

## herdr 側のセットアップ（必須）

HerdWatch は herdr のローカルソケット API（NDJSON / JSON-RPC）を読み、エージェント状態を鏡写しに表示する。ソケットが存在しないと接続できない。

### 1. herdr をインストールする

公式ドキュメント: https://herdr.dev/ja/docs/install/

```bash
# macOS / Linux
curl -fsSL https://herdr.dev/install.sh | sh
# または
brew install herdr
```

バージョン確認:

```bash
herdr --version
```

### 2. herdr サーバーを起動しておく

HerdWatch が接続するソケットは herdr の **サーバープロセスが起動中にのみ存在** する。ターミナルで `herdr` を実行してセッションを開いておくこと。

```bash
herdr
```

サーバーを止めるとソケットが消え、HerdWatch は再接続を試み続ける（herdr を再起動すれば自動復帰する）。

### 3. ソケットパスを確認する

HerdWatch はデフォルトで herdr の **デフォルトセッション** のソケットを見る:

```
~/.config/herdr/herdr.sock
```

**名前付きセッション**（`herdr session attach <name>`）を使っている場合はソケットパスが異なる:

```
~/.config/herdr/sessions/<name>/herdr.sock
```

この場合は HerdWatch の設定画面「ソケットパス」に上記パスを入力する（空 = デフォルトセッション）。ソケットパスの解決順は herdr の仕様に従う（`HERDR_SOCKET_PATH` / `HERDR_SESSION` で上書き可能だが、HerdWatch 側では設定画面の値が最優先）。

### 4. エージェントインテグレーションを入れる（推奨・状態精度に直結）

herdr はインテグレーションなしでもスクリーンマニフェストでエージェント状態を推定するが、フック/プラグインによるライフサイクル権威を持つエージェントでは **インテグレーションを入れると状態が正確になる**。HerdWatch は herdr の状態をそのまま鏡写しするため（ADR-0001）、herdr 側の精度がそのままキャラ表示の精度になる。

使っているエージェントごとにインストールする:

```bash
herdr integration install claude
herdr integration install codex
herdr integration install copilot
herdr integration install devin
herdr integration install pi
herdr integration install omp
herdr integration install kimi
herdr integration install opencode
herdr integration install kilo
herdr integration install hermes
herdr integration install droid
herdr integration install qodercli
herdr integration install cursor
```

状態とインストール済みバージョンを確認:

```bash
herdr integration status
```

対応エージェントと「どのシグナルが状態の権威か」の一覧は https://herdr.dev/ja/docs/agents/ を参照。

> **注意（コメント吹き出しについて）**: `pane.report_agent` の `message` は書き込み専用で `pane.list` / `pane.get` / `agent.get` / `pane.agent_status_changed` のいずれにも現れない（実測）。読めるのは `custom_status`（最大32文字）のみだが、Claude Code 等の組み込み対応エージェントは自動報告しないため、ユーザー hook から明示的に `report-agent` を呼ばない限り常に空になる。よって HerdWatch にキャラのコメント吹き出し機能は実装していない。

### 5. herdr CLI を PATH に通す（フォールバック用）

キャラクターをタップしたときのフォーカス動作は:

1. ソケット API `agent.focus` を叩く
2. 失敗時のみ `herdr agent focus <pane_id>` CLI にフォールバック

CLI フォールバックは次の順で `herdr` バイナリを探す:

- `~/homebrew/bin/herdr`
- `/opt/homebrew/bin/herdr`
- `/usr/local/bin/herdr`

ソケット経由が基本路線なので必須ではないが、`brew install herdr` などで PATH に置いておくと保険になる。

## HerdWatch アプリの設定

設定画面から以下を調整できる:

- **ターミナルアプリ**: キャラタップ時に前面化するターミナル（空 = 起動中の既知ターミナルを自動選択: iTerm2 / Ghostty / WezTerm / kitty / Alacritty / Warp / ターミナル）
- **ソケットパス**: 名前付きセッション利用時のみ変更（空 = `~/.config/herdr/herdr.sock`）
- **常に最前面** / **キャラサイズ** / **背景** / **自動再配置** / **working 経過時間表示** / **表示言語**

## iOS Companion（HerdWatchIOS）

Mac アプリと iOS アプリを同じ Wi-Fi 上で MultipeerConnectivity（ローカル P2P・外部サーバなし）で連携させる。真実源は Mac の PastureStore のまま（ADR-0001）。iOS は状態表示＋タップフォーカスのみ。

- サービス型: `hrdwtch-cmp`（Bonjour `_hrdwtch-cmp._tcp`）
- iOS 側は `NSLocalNetworkUsageDescription` / `NSBonjourServices` を Info.plist で宣言済み（iOS 14+ のローカネットワーク権限）
- iOS 側に herdr のセットアップは不要（Mac 側が herdr と通信し、iOS は Mac からスナップショットを受け取る）

## ビルド

リポジトリルートで XcodeGen でプロジェクトを再生成してからビルドする（`.xcodeproj` は生成物・手編集禁止）。

```bash
# プロジェクト再生成（ファイル追加時は必須）
xcodegen generate -s HerdWatch.yml      # macOS アプリ
xcodegen generate -s HerdWatchIOS.yml   # iOS アプリ

# macOS アプリ
xcodebuild build -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'
xcodebuild test  -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'

# iOS アプリ
xcodebuild build -project HerdWatchIOS.xcodeproj -scheme HerdWatchIOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 共有パッケージの単体テスト
cd Packages/HerdWatchShared && swift test
```

ローカルは ad-hoc 署名（`CODE_SIGN_IDENTITY = "-"`）。ルートに2つの `.xcodeproj` があるため `xcodebuild` には `-project` を明示する。

## トラブルシューティング

### キャラが1匹も表示されない / 接続できない

1. `herdr` サーバーが起動中か確認（`herdr status`）。ソケットはサーバー起動中のみ存在する。
2. ソケットファイルがあるか確認: `ls ~/.config/herdr/herdr.sock`
3. 名前付きセッションを使っている場合は設定画面のソケットパスを `~/.config/herdr/sessions/<name>/herdr.sock` に設定する。
4. herdr ログ: `~/.config/herdr/herdr.log`, `herdr-server.log`, `herdr-client.log`

### 状態が正しくない / blocked にならない

herdr の状態精度そのもの。HerdWatch 側では直さない（ADR-0001）。

```bash
herdr agent list                              # herdr が見ているエージェント一覧
herdr agent explain <target> --json           # なぜその状態になったか
herdr integration status                      # インテグレーション未導入なら入れる
```

スクリーンマニフェスト方式のエージェントでは `blocked` 判定は厳格で、未知のプロンプト形は `idle` にフォールバックする（herdr の仕様）。インテグレーションを入れるとライフサイクルフックが権威になり精度が上がる。

### キャラをタップしても pane に飛ばない

1. ターミナルアプリが起動しているか（HerdWatch は起動中のターミナルを前面化する）。
2. herdr CLI が探索パスにあれば CLI フォールバックが効く（`~/homebrew/bin/herdr` / `/opt/homebrew/bin/herdr` / `/usr/local/bin/herdr`）。
3. `herdr agent focus <pane_id>` を手動で実行して herdr 側の挙動を確認。

## 関連ドキュメント

- [CONTEXT.md](CONTEXT.md) — 用語定義
- [docs/adr/](docs/adr/) — 設計判断の正本
- [CLAUDE.md](CLAUDE.md) — 実装ルール・herdr プロトコルの実測制約
- herdr 公式ドキュメント: https://herdr.dev/ja/docs/
