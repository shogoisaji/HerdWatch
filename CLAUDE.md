# HerdWatch — プロジェクトルール

herdr上のAIエージェントをピクセルアート家畜キャラで可視化するmacOSアプリ。
用語は [`CONTEXT.md`](./CONTEXT.md)、設計判断は [`docs/adr/`](./docs/adr/) が正本。

## スタック

- Swift 5モード / SwiftUI（描画はCanvas+TimelineView）+ AppKit（ウィンドウレベル・NSWorkspace）
- 最小OS: macOS 26.0 / iOS 26.0 / 非サンドボックス（unixソケット・NSWorkspaceアクティベーション・herdr CLI起動のため）
- herdr Socket API: `~/.config/herdr/herdr.sock`、NDJSON JSON-RPC

## リポジトリ構成（モノレポ + SwiftPM ローカルパッケージ）

```
HerdWatch/                       ← リポジトリルート
├── HerdWatch.yml                ← XcodeGen定義: macOSアプリ（正本）
├── HerdWatchIOS.yml             ← XcodeGen定義: iOSアプリ（正本）
├── HerdWatch.xcodeproj          ← 生成物（gitignore済み・手編集禁止）
├── HerdWatchIOS.xcodeproj       ← 生成物（gitignore済み・手編集禁止）
├── HerdWatch/                   ← macOSアプリ本体（Mac専用）
├── HerdWatchIOS/                ← iOS Companionアプリ
├── HerdWatchTests/              ← macOSアプリのテスト（Mac専用ロジック）
├── Packages/HerdWatchShared/    ← SwiftPM ローカルパッケージ（Mac/iOS共有コード）
│   ├── Package.swift
│   ├── Sources/HerdWatchShared/ ← Domain・UI・Socket・Companion・Support
│   └── Tests/HerdWatchSharedTests/ ← 共有コードの単体テスト（swift test で実行可能）
└── docs/adr/                    ← 設計判断の正本
```

- 共有コードは `Packages/HerdWatchShared`（SwiftPM ローカルパッケージ）で管理。
  Mac/iOS両アプリがパッケージ依存する。パッケージ内の型は `public` で公開。
- Mac専用ファイル（Socket層・Companionホスト・Settings・AppKit UI・HerdWatchApp）は `HerdWatch/` 配下。
- iOS専用ファイル（CompanionClient・CompanionStore・CompanionPastureView・HerdWatchIOSApp）は `HerdWatchIOS/` 配下。

## ビルド・検証（リポジトリルートで実行）

```bash
# XcodeGen プロジェクト再生成（ファイル追加時は必須）
xcodegen generate -s HerdWatch.yml      # macOSアプリ
xcodegen generate -s HerdWatchIOS.yml   # iOSアプリ

# macOSアプリ
xcodebuild build -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'
xcodebuild test  -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'

# iOSアプリ
xcodebuild build -project HerdWatchIOS.xcodeproj -scheme HerdWatchIOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# 共有パッケージ単体テスト
cd Packages/HerdWatchShared && swift test
```

- `HerdWatch.yml` / `HerdWatchIOS.yml` が正本。`.xcodeproj` は生成物（gitignore済み）。`project.pbxproj` を手で編集しない。
- ローカルはad-hoc署名（`CODE_SIGN_IDENTITY = "-"`）。
- ルートに2つの `.xcodeproj` があるため、xcodebuild には `-project` を明示する。

## iOS Companion連携（MultipeerConnectivity）

MacアプリとiOSアプリ(`HerdWatchIOS`)を同じWi-Fi上でMultipeerConnectivity（ローカルP2P・外部サーバなし）で連携させる。真実源はMacのPastureStoreのまま（ADR-0001準拠）。iOSは状態表示+タップフォーカスのみ。

- 通信プロトコル型は `Packages/HerdWatchShared/Sources/HerdWatchShared/Companion/CompanionProtocol.swift`（Mac/iOS両ターゲットが共有）。NDJSON1行=1JSONメッセージ。`CompanionSnapshot`(Mac→iOS)と`CompanionFocusCommand`(iOS→Mac)を`CompanionMessage`エンベロープで包む。
- Mac側: `HerdWatch/Companion/CompanionLink.swift`(Multipeerアドバイザ・IOラッパ) + `CompanionHostService.swift`(PastureStore観察→スナップショット配信、iOSからのfocus命令→HerdrFocusService委譲)。純粋ロジックは `CompanionHostSnapshotBuilder` / `CompanionHostRouter` に分離し単体テスト済み。
- iOS側: `HerdWatchIOS/CompanionClient.swift`(Multipeerブラウザ) + `CompanionStore.swift`(受信スナップショットの鏡写し保持) + `CompanionPastureView.swift`(読み取り専用描画+シングルタップでfocus送信)。
- サービス型 `hrdwtch-cmp`。iOSは `NSLocalNetworkUsageDescription` / `NSBonjourServices`(`_hrdwtch-cmp._tcp`)をInfo.plistで宣言済み（iOS 14+のローカルネットワーク権限）。
- コード共有: Domain層・スプライト描画(`CharacterSprite`/`SpriteRenderer`/`OverlayBadge`/`AgentAnimator`/`HitTest`)・`AnyRNG`・`HerdrModels`・`WorkingElapsedFormatter`・`CompanionProtocol`は `HerdWatchShared` パッケージでmacOS/iOS両対応。AppKit依存(`NSWorkspace`/`NSView`/`NSMenu`)・Socket層・Companionホスト・SettingsはMac側のみ。

## herdrプロトコルの実測制約（実装が依存する前提）

- 単発RPCはレスポンス直後にサーバが接続を閉じる → 1コール=1接続。
- `events.subscribe` は1接続につき1回だけ。2回目は無言EOF → 購読変更は接続ごと張り替え。
- `pane.agent_status_changed` 購読は `pane_id` 必須。`agent.focus` のparamsは `target`、`workspace.focus` は `workspace_id`。
- pushイベントは `{"data": {...}, "event": "<名前>"}` 形式（レスポンスの `id/result` とは別）。イベント名は `pane.agent_status_changed` のみドット表記、他は `pane_focused` 等アンダースコア表記（実測）。
- `pane.agent_status_changed` の data は `{agent, agent_status, pane_id, workspace_id}` で `revision` を含まない。実測ワイヤは `HerdWatchTests/Fixtures/` に保存済み（done→閲覧→idle の遷移実例は `events_sample.ndjson`）。
- コーデックは寛容にデコードする（未知フィールド無視・未知イベントtypeはlog-and-skip）。docsと実装の乖離が実証済みのため。
- `pane.report_agent`（CLI: `herdr pane report-agent`）の `message` パラメータは**書き込み専用**。`pane.list`/`pane.get`/`agent.get`/`pane.agent_status_changed` イベントのいずれにも現れない（実測、孤立テストpaneで検証済み）。読める唯一のコメント欄は `custom_status`（最大32文字）だが、Claude Code等の組み込み対応エージェントの状態判定はターミナル画面のパターンマッチングによるもので `custom_status` を自動報告しない（herdr公式ドキュメントで確認）。ユーザー側でhookから明示的に `report-agent` を呼ばない限り常に空になるため、**キャラのコメント吹き出し機能は実装しない判断**（2026-07-02）。

## 禁止事項

- アプリ側で状態の未読管理・永続化をしない（ADR-0001。永続化はキャラ割当のみ）。
- pane内容の読み取り（`pane.read` 等）や外部送信をしない。状態表示に必要なメタデータのみ扱う。
