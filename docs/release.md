# HerdWatch リリース運用

CodexBar の管理手法（GitHub Releases 正本 + `release: published` トリガ + Homebrew Cask 別 tap）を参考に、
HerdWatch は **Developer ID 署名 + notarization + Sparkle 自動更新 + Homebrew Cask** の組み合わせで配信する。

## 配信経路

| 経路 | URL | 更新タイミング |
|---|---|---|
| GitHub Releases (DMG/zip/appcast) | https://github.com/shogoisaji/HerdWatch/releases | `release: published` で `release.yml` が自動ビルド・署名・アップロード |
| Homebrew Cask | `brew install --cask shogoisaji/herdwatch/herdwatch` | `release.yml` から tap リポジトリへ `workflow_dispatch` → `update-cask.yml` が Cask を更新 |
| Sparkle アプリ内自動更新 | `SUFeedURL` = `releases/latest/download/appcast.xml` | appcast.xml を各リリースに添付、アプリが起動時に確認 |

Mac App Store は非サンドボックス（unix ソケット・NSWorkspace・herdr CLI 起動）のため対象外。

## リリース手順

### 1. バージョンを上げる

`HerdWatch.yml` の `MARKETING_VERSION`（と必要なら `CURRENT_PROJECT_VERSION`）を更新。

```yaml
settings:
  base:
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "2"
```

コミットして main にマージ（CI がビルド+テストを検証）。

### 2. タグを打って Release を publish

```bash
git tag v0.2.0
git push origin v0.2.0
# GitHub 上で Release を作成（publish すると release.yml が走る）
gh release create v0.2.0 --generate-notes --title "0.2.0"
```

`release.yml` が自動で:
1. xcodegen 再生成
2. Developer ID 署名 + Hardened Runtime + entitlements で archive
3. notarize + staple（app と DMG 両方）
4. Sparkle update zip を Ed25519 で署名
5. appcast.xml 生成
6. `gh release upload` で DMG / zip / sha256 / appcast.xml を添付
7. homebrew-herdwatch リポジトリへ `workflow_dispatch` で Cask 更新を指示

### 3. 確認

- Release ページに `HerdWatch-<ver>.dmg`, `.zip`, `.sha256`, `appcast.xml` が揃っている
- `brew install --cask shogoisaji/herdwatch/herdwatch` で新版が入る
- 既存ユーザーのアプリが Sparkle でアップデートを検知する

## 必要な GitHub Secrets（shogoisaji/HerdWatch）

リポジトリの Settings → Secrets and variables → Actions → New repository secret で設定する。

| Secret 名 | 値 | 用途 |
|---|---|---|
| `APPLE_DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application 証明書 (.p12) を base64 化したもの | CI 上で keychain に import して署名 |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | 上記 .p12 のエクスポートパスワード | 証明書 import 時 |
| `APPLE_DEVELOPER_ID_NAME` | `Developer ID Application: Your Name (TEAMID)` | `CODE_SIGN_IDENTITY` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `DEVELOPMENT_TEAM` / notarytool |
| `APPLE_ID` | notarization 用 Apple ID | `notarytool submit` |
| `APPLE_ID_PASSWORD` | App 専用パスワード (appleid.apple.com で生成) | `notarytool submit` |
| `SPARKLE_PRIVATE_KEY_PEM` | Sparkle Ed25519 秘密鍵（`generate_keys -x` でエクスポートした .pem の内容） | `sign_update --ed-key-file` |
| `HOMEBREW_TAP_TOKEN` | homebrew-herdwatch リポジトリへ dispatch するための PAT（`repo` + `workflow` スコープ） | Cask 自動更新 |

### 証明書・鍵の準備手順

#### Developer ID 証明書

1. Apple Developer → Certificates, Identifiers & Profiles → 新規証明書 `Developer ID Application`
2. Keychain Access で鍵を書き出し (.p12、パスワード設定)
3. base64 化: `base64 -i developer-id.p12 | pbcopy` → `APPLE_DEVELOPER_ID_CERT_P12_BASE64` に貼り付け

#### notarization 用 App 専用パスワード

1. https://appleid.apple.com → サインイン → アプリ専用パスワード → 生成
2. `APPLE_ID_PASSWORD` に設定

#### Sparkle Ed25519 鍵

鍵ペアは既に生成済み（公開鍵は `HerdWatch.yml` の `SUPublicEDKey` に埋込済み）。
秘密鍵を CI secret に登録する:

```bash
# ローカルで（鍵を Keychain に持っている端末で）
generate_keys -x /tmp/ed25519_priv.pem
cat /tmp/ed25519_priv.pem
# 出力内容を SPARKLE_PRIVATE_KEY_PEM に貼り付け
```

> 公開鍵: `HerdWatch.yml` の `SUPublicEDKey`（`info:` → Info.plist に生成）
> 秘密鍵は絶対にコミットしない（`.gitignore` で `*.pem` 等を除外済み）。

#### Homebrew tap 用 PAT

1. https://github.com/settings/tokens → Generate new token (classic) → `repo` + `workflow` スコープ
2. `HOMEBREW_TAP_TOKEN` に設定（shogoisaji/HerdWatch リポジトリの secret）

## ローカルリリース（CI 使わない場合）

`scripts/release-local.sh` が R2/static ホスティング向けの同等のパイプラインを提供する。
`release/release.env.example` を `release/release.env` にコピーして各値を埋める。

```bash
cp release/release.env.example release/release.env
# release.env を編集
./scripts/release-local.sh
```

CI 運用が基本だが、緊急時やオフライン署名に使う。
