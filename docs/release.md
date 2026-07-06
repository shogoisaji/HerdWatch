# HerdWatch Release Operations

HerdWatch is distributed via **Developer ID signing + notarization + Sparkle
auto-update + Homebrew Cask**, using GitHub Releases as the source of truth.

## Distribution channels

| Channel | URL | Update trigger |
|---|---|---|
| GitHub Releases (DMG/zip/appcast) | https://github.com/shogoisaji/HerdWatch/releases | `release: published` triggers `release.yml` — auto build, sign, upload |
| Homebrew Cask | `brew install --cask shogoisaji/herdwatch/herdwatch` | `release.yml` dispatches `workflow_dispatch` to tap repo → `update-cask.yml` updates the Cask |
| Sparkle in-app auto-update | `SUFeedURL` = `releases/latest/download/appcast.xml` | appcast.xml attached to each release; app checks on launch |

The Mac App Store is not an option — the app is non-sandboxed (unix socket, NSWorkspace activation, herdr CLI launch).

## Release procedure

### 1. Bump the version

Update `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION` if needed) in `project.yml`:

```yaml
settings:
  base:
    MARKETING_VERSION: "0.2.0"
    CURRENT_PROJECT_VERSION: "2"
```

Commit and merge to main (CI validates build + tests).

### 2. Tag and publish a Release

```bash
git tag v0.2.0
git push origin v0.2.0
# Create a Release on GitHub (publishing triggers release.yml)
gh release create v0.2.0 --generate-notes --title "0.2.0"
```

`release.yml` automatically:
1. Regenerates the Xcode project with xcodegen
2. Archives with Developer ID signing + Hardened Runtime + entitlements
3. Notarizes + staples (both app and DMG)
4. Signs the Sparkle update zip with Ed25519
5. Generates appcast.xml
6. Uploads DMG / zip / sha256 / appcast.xml to the Release
7. Dispatches a Cask update to the homebrew-herdwatch repository

### 3. Verify

- Release page has `HerdWatch-<ver>.dmg`, `.zip`, `.sha256`, `appcast.xml`
- `brew install --cask shogoisaji/herdwatch/herdwatch` installs the new version
- Existing users' apps detect the update via Sparkle

## Required GitHub Secrets (shogoisaji/HerdWatch)

Set these in Settings → Secrets and variables → Actions → New repository secret.

| Secret | Value | Used for |
|---|---|---|
| `APPLE_DEVELOPER_ID_CERT_P12_BASE64` | Developer ID Application certificate (.p12) base64-encoded | Import to CI keychain for signing |
| `APPLE_DEVELOPER_ID_CERT_PASSWORD` | Export password for the .p12 | Certificate import |
| `APPLE_DEVELOPER_ID_NAME` | `Developer ID Application: Your Name (TEAMID)` | `CODE_SIGN_IDENTITY` |
| `APPLE_TEAM_ID` | Apple Developer Team ID | `DEVELOPMENT_TEAM` / notarytool |
| `APPLE_ID` | Apple ID for notarization | `notarytool submit` |
| `APPLE_ID_PASSWORD` | App-specific password (generated at appleid.apple.com) | `notarytool submit` |
| `SPARKLE_PRIVATE_KEY_PEM` | Sparkle Ed25519 private key (exported via `generate_keys -x`) | `sign_update --ed-key-file` |
| `HOMEBREW_TAP_TOKEN` | PAT with `repo` + `workflow` scopes to dispatch to homebrew-herdwatch | Cask auto-update |

### Preparing credentials

#### Developer ID certificate

1. Apple Developer → Certificates, Identifiers & Profiles → create a `Developer ID Application` certificate
2. Export the key from Keychain Access as .p12 (set a password)
3. Base64-encode: `base64 -i developer-id.p12 | pbcopy` → paste into `APPLE_DEVELOPER_ID_CERT_P12_BASE64`

#### Notarization app-specific password

1. https://appleid.apple.com → sign in → App-Specific Passwords → generate
2. Set `APPLE_ID_PASSWORD`

#### Sparkle Ed25519 key

The key pair is already generated (public key is embedded in `project.yml` as `SUPublicEDKey`).
Register the private key as a CI secret:

```bash
# On the machine that has the key in Keychain
generate_keys -x /tmp/ed25519_priv.pem
cat /tmp/ed25519_priv.pem
# Paste the output into SPARKLE_PRIVATE_KEY_PEM
```

> Public key: `project.yml` `SUPublicEDKey` (→ Info.plist via `info:`)
> Never commit the private key (`.gitignore` excludes `*.pem`).

#### Homebrew tap PAT

1. https://github.com/settings/tokens → Generate new token (classic) → `repo` + `workflow` scopes
2. Set `HOMEBREW_TAP_TOKEN` (in the shogoisaji/HerdWatch repo secrets)

## Local release (without CI)

`scripts/release-local.sh` provides an equivalent pipeline for R2/static hosting.
Copy `release/release.env.example` to `release/release.env` and fill in values.

```bash
cp release/release.env.example release/release.env
# Edit release.env
./scripts/release-local.sh
```

CI is the primary path; use this for emergencies or offline signing.
