# HerdWatch

[![Latest release](https://img.shields.io/github/v/release/shogoisaji/HerdWatch?style=flat-square)](https://github.com/shogoisaji/HerdWatch/releases/latest)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000?style=flat-square)](https://github.com/shogoisaji/HerdWatch/releases/latest)
[![Homebrew](https://img.shields.io/badge/brew-shogoisaji%2Fherdwatch%2Fherdwatch-orange?style=flat-square)](https://github.com/shogoisaji/homebrew-herdwatch)
[![License: MIT](https://img.shields.io/badge/license-MIT-6e5aff?style=flat-square)](LICENSE)
[![CI](https://img.shields.io/github/actions/workflow/status/shogoisaji/HerdWatch/ci.yml?branch=main&label=CI&style=flat-square)](https://github.com/shogoisaji/HerdWatch/actions/workflows/ci.yml)

A macOS app that visualizes AI coding agents running in [herdr](https://herdr.dev/) as pixel-art livestock characters in a dedicated window. Tell at a glance which pane is done and which one needs your attention — tap a character to jump straight to that pane.

HerdWatch is a mirror of herdr's state. It does not track its own unread state or persist anything beyond character assignments ([ADR-0001](docs/adr/0001-herdr-as-single-source-of-truth.md)). **herdr must be set up first.**

> Design decisions live in [CONTEXT.md](CONTEXT.md) and [docs/adr/](docs/adr/).

## Install

### Homebrew (recommended)

```bash
brew tap shogoisaji/herdwatch
brew install --cask herdwatch
```

Update:

```bash
brew upgrade --cask herdwatch
```

### GitHub Releases

Download `HerdWatch-<version>.dmg` from <https://github.com/shogoisaji/HerdWatch/releases/latest> and drag to install.

### In-app updates

HerdWatch ships with [Sparkle](https://sparkle-project.org/). When a new release is published, running apps check the appcast and prompt to update. You can also check manually via the menu item **Check for Updates…**.

## Requirements

- macOS 26.0 or later (non-sandboxed)
- [herdr](https://herdr.dev/) installed and its server running

## herdr setup (required)

HerdWatch reads herdr's local socket API (NDJSON / JSON-RPC) and mirrors agent state. It cannot connect unless the socket exists.

### 1. Install herdr

Docs: <https://herdr.dev/docs/install/>

```bash
curl -fsSL https://herdr.dev/install.sh | sh
# or
brew install herdr
```

Verify:

```bash
herdr --version
```

### 2. Keep the herdr server running

The socket only exists while the herdr server process is running. Open a session in a terminal:

```bash
herdr
```

Stopping the server removes the socket; HerdWatch keeps retrying and recovers automatically once herdr restarts.

### 3. Check the socket path

By default HerdWatch watches the default session socket:

```
~/.config/herdr/herdr.sock
```

For a **named session** (`herdr session attach <name>`):

```
~/.config/herdr/sessions/<name>/herdr.sock
```

Enter that path in HerdWatch's Settings → **Socket path** (empty = default session).

### 4. Install agent integrations (recommended)

herdr can estimate agent state from the screen manifest without integrations, but agents that own their lifecycle via hooks/plugins report state more accurately when the integration is installed. HerdWatch mirrors herdr exactly (ADR-0001), so herdr's accuracy is HerdWatch's accuracy.

Install per agent you use:

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

Check status:

```bash
herdr integration status
```

See <https://herdr.dev/docs/agents/> for the full list and which signal is authoritative per agent.

> **Note on comment bubbles:** `pane.report_agent`'s `message` is write-only and never appears in `pane.list` / `pane.get` / `agent.get` / `pane.agent_status_changed` (verified by testing). The only readable field is `custom_status` (max 32 chars), but built-in agents like Claude Code do not auto-report it, so it is always empty unless a user hook calls `report-agent` explicitly. HerdWatch therefore does not implement character comment bubbles.

### 5. Put `herdr` on PATH (fallback)

Tapping a character focuses the pane via:

1. Socket API `agent.focus`
2. On failure, falls back to `herdr agent focus <pane_id>` CLI

The CLI is searched in this order:

- `~/homebrew/bin/herdr`
- `/opt/homebrew/bin/herdr`
- `/usr/local/bin/herdr`

Socket is the primary path, so this is optional, but `brew install herdr` gives you a safety net.

## App settings

Adjustable in Settings:

- **Terminal app**: which terminal to bring to front on character tap (empty = auto-select a known running terminal: iTerm2 / Ghostty / WezTerm / kitty / Alacritty / Warp / Terminal)
- **Socket path**: only for named sessions (empty = `~/.config/herdr/herdr.sock`)
- **Always on top** / **Character size** / **Background** / **Auto rearrange** / **Show working elapsed** / **Display language**

## Build

Regenerate the Xcode project with XcodeGen before building (`.xcodeproj` is generated, do not edit by hand).

```bash
# Regenerate project (required when files are added)
xcodegen generate

# Build
xcodebuild build -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'
xcodebuild test  -project HerdWatch.xcodeproj -scheme HerdWatch -destination 'platform=macOS'

# Shared package tests
cd Packages/HerdWatchShared && swift test
```

Local builds use ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`).

## Troubleshooting

### No characters show / cannot connect

1. Is the herdr server running? (`herdr status`) The socket only exists while it is.
2. Does the socket file exist? `ls ~/.config/herdr/herdr.sock`
3. Using a named session? Set Settings → Socket path to `~/.config/herdr/sessions/<name>/herdr.sock`.
4. herdr logs: `~/.config/herdr/herdr.log`, `herdr-server.log`, `herdr-client.log`

### State is wrong / never goes `blocked`

This is herdr's accuracy, not HerdWatch's. HerdWatch does not fix it (ADR-0001).

```bash
herdr agent list                              # agents herdr sees
herdr agent explain <target> --json           # why it's in that state
herdr integration status                      # install integrations if missing
```

Screen-manifest agents judge `blocked` strictly and fall back to `idle` for unknown prompt shapes (herdr's spec). Integrations make lifecycle hooks authoritative and improve accuracy.

### Tapping a character does not jump to the pane

1. Is your terminal app running? HerdWatch brings a running terminal to front.
2. If `herdr` is on PATH, the CLI fallback works (`~/homebrew/bin/herdr` / `/opt/homebrew/bin/herdr` / `/usr/local/bin/herdr`).
3. Try `herdr agent focus <pane_id>` manually to check herdr's behavior.

## Documentation

- [CONTEXT.md](CONTEXT.md) — terminology
- [docs/adr/](docs/adr/) — design decisions
- [docs/release.md](docs/release.md) — release & distribution
- [CLAUDE.md](CLAUDE.md) — implementation rules and measured herdr protocol constraints
- herdr docs: <https://herdr.dev/docs/>
