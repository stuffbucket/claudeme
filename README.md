# Claudeme

**Open in Claude Code** — a native macOS Finder toolbar app that launches Claude Code in the current directory.

## Installation

### Via Homebrew

```bash
brew install stuffbucket/tap/claudeme
```

### Manual

```bash
git clone https://github.com/stuffbucket/claudeme.git
cd claudeme
make install
```

## Setup

1. Open `/Applications` in Finder
2. Hold **⌘** and drag "Open in Claude Code" to the Finder toolbar
3. Navigate to any project folder
4. Click the toolbar icon to open Claude Code there

Double-click the app (from /Applications or Downloads) to access **Settings**.

## Features

- **One-click Claude Code** — Click the toolbar icon in any folder
- **Multiple terminal support** — Terminal, iTerm, Warp, Kitty, Alacritty, Ghostty
- **Terminal profiles** — Choose your preferred Terminal.app profile (Clear Dark, Clear Light, etc.)
- **Custom command** — Configure `claude`, `agency claude`, or any custom command
- **Default directory** — Creates and configures a default project folder (e.g., `~/Claude`)
- **Trusted directories manager** — View and remove directories from Claude's trust list
- **Auto-install Claude** — Prompts to install Claude Code CLI if not found

## Configuration

Settings are stored in `~/.config/openinclaudecode/settings.json`:

```json
{
  "terminal": "Terminal",
  "terminalProfile": "Clear Dark",
  "claudeCommand": "claude",
  "defaultDirectory": "~/Claude"
}
```

Access settings by double-clicking the app from /Applications.

## Safety

The app refuses to launch Claude Code in protected directories:
- Home folder (`~/`)
- Root (`/`)
- System directories (`/System`, `/Library`, `/Applications`, etc.)

This prevents accidentally giving Claude Code full system access.

## Requirements

- macOS 11.0 (Big Sur) or later
- [Claude Code CLI](https://claude.ai/install.sh)

## License

MIT
