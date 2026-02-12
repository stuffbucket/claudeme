#!/bin/bash
# Build script for Open in Claude Code app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Open in Claude Code"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Compile Swift
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/OpenInClaudeCode" \
    -target arm64-apple-macosx12.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework ScriptingBridge \
    "$SCRIPT_DIR/main.swift"

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Ad-hoc sign
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✓ Built: $APP_BUNDLE"
echo ""
echo "To install:"
echo "  cp -R '$APP_BUNDLE' /Applications/"
echo ""
echo "Then Cmd-drag the app from /Applications to your Finder toolbar."
