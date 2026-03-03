#!/bin/bash
# Build script for Open in Claude Code app
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Open in Claude Code"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Options
SIGN_IDENTITY="${SIGN_IDENTITY:--}"  # ad-hoc by default
UNIVERSAL="${UNIVERSAL:-0}"
CREATE_DMG="${CREATE_DMG:-0}"
DMG_NAME="${DMG_NAME:-Claudeme}"

echo "Building $APP_NAME..."

# Clean
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

SDK_PATH=$(xcrun --show-sdk-path)

if [ "$UNIVERSAL" = "1" ]; then
    echo "  Building universal binary (arm64 + x86_64)..."
    swiftc \
        -o "$BUILD_DIR/OpenInClaudeCode-arm64" \
        -target arm64-apple-macosx12.0 \
        -sdk "$SDK_PATH" \
        -framework Cocoa \
        -framework ScriptingBridge \
        "$SCRIPT_DIR/main.swift"

    swiftc \
        -o "$BUILD_DIR/OpenInClaudeCode-x86_64" \
        -target x86_64-apple-macosx12.0 \
        -sdk "$SDK_PATH" \
        -framework Cocoa \
        -framework ScriptingBridge \
        "$SCRIPT_DIR/main.swift"

    lipo -create \
        "$BUILD_DIR/OpenInClaudeCode-arm64" \
        "$BUILD_DIR/OpenInClaudeCode-x86_64" \
        -output "$APP_BUNDLE/Contents/MacOS/OpenInClaudeCode"

    rm "$BUILD_DIR/OpenInClaudeCode-arm64" "$BUILD_DIR/OpenInClaudeCode-x86_64"
else
    swiftc \
        -o "$APP_BUNDLE/Contents/MacOS/OpenInClaudeCode" \
        -target arm64-apple-macosx12.0 \
        -sdk "$SDK_PATH" \
        -framework Cocoa \
        -framework ScriptingBridge \
        "$SCRIPT_DIR/main.swift"
fi

# Copy Info.plist
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy icon
if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Code sign
ENTITLEMENTS="$SCRIPT_DIR/app.entitlements"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "  Ad-hoc signing..."
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"
else
    echo "  Signing with identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
fi

echo "✓ Built: $APP_BUNDLE"

# Create DMG
if [ "$CREATE_DMG" = "1" ]; then
    DIST_DIR="${DIST_DIR:-$SCRIPT_DIR/../dist}"
    mkdir -p "$DIST_DIR"
    DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
    DMG_STAGING="$BUILD_DIR/dmg-staging"
    echo "  Creating DMG..."

    rm -rf "$DMG_STAGING"
    mkdir -p "$DMG_STAGING"
    cp -R "$APP_BUNDLE" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_STAGING"

    # Sign the DMG itself if using a real identity
    if [ "$SIGN_IDENTITY" != "-" ]; then
        codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH"
    fi

    echo "✓ DMG: $DMG_PATH"
fi

echo ""
echo "To install:"
echo "  cp -R '$APP_BUNDLE' /Applications/"
echo ""
echo "Then Cmd-drag the app from /Applications to your Finder toolbar."
