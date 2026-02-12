# claudeme

Simple Claude Code launcher for macOS. Creates a dedicated `~/Claude` folder for your projects and provides easy CLI access.

## What it does

- Creates `~/Claude` folder for your Claude Code projects
- Tags it orange in Finder for easy identification
- Provides CLI to launch Claude Code safely in project folders
- Prevents accidentally trusting dangerous directories like `~/` or `/`

## Installation

### Via Homebrew (recommended)

```bash
brew tap stuffbucket/tap
brew install claudeme
claudeme setup
```

### Manual installation

```bash
git clone https://github.com/stuffbucket/claudeme.git
cd claudeme
chmod +x bin/claudeme
sudo cp bin/claudeme /usr/local/bin/
claudeme setup
```

## Usage

```bash
# One-time setup (creates ~/Claude folder)
claudeme setup

# Launch Claude Code in ~/Claude
claudeme launch

# Launch in a specific project
claudeme ~/Claude/my-project

# Launch in current directory
claudeme here
```

## One-click Finder integration

The project includes **Open in Claude Code**, a native macOS app for your Finder toolbar:

### Build and install

```bash
cd app && ./build.sh
cp -R 'build/Open in Claude Code.app' /Applications/
```

### Add to Finder toolbar

1. Open `/Applications` in Finder
2. Hold **Cmd** and drag "Open in Claude Code" to the Finder toolbar
3. Click it while viewing any folder to open Claude Code there

The app automatically:
- Gets the selected folder (or current folder if nothing selected)
- Opens Terminal
- Runs `claude` in that directory

## Safety features

Claudeme refuses to launch Claude Code in dangerous directories:
- Home folder (`~/`)
- Root (`/`)
- System directories (`/System`, `/Library`, `/Applications`, etc.)

This prevents accidentally giving Claude Code access to your entire system.

## Requirements

- macOS 10.15 (Catalina) or later
- Claude Code CLI: `npm install -g @anthropic-ai/claude-code`

## License

MIT
