SHELL := /bin/bash

.DEFAULT_GOAL := help

APP_NAME := Open in Claude Code
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

# Signing identities (auto-detected from keychain)
APP_SIGN_ID ?= $(shell security find-identity -v -p codesigning | grep -o '"Developer ID Application:[^"]*"' | head -1 | tr -d '"')
PKG_SIGN_ID ?= $(shell security find-identity -v | grep -o '"Developer ID Installer:[^"]*"' | head -1 | tr -d '"')

.PHONY: help setup build install uninstall sign dmg pkg release clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## First-time setup for contributors
	@echo "Setting up development environment..."
	@git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true
	@echo "✓ Setup complete"

build: ## Build the macOS app
	@./app/build.sh

sign: ## Build signed app
	@test -n "$(APP_SIGN_ID)" || { echo "No Developer ID Application certificate found in keychain"; exit 1; }
	@echo "Signing with: $(APP_SIGN_ID)"
	@SIGN_IDENTITY="$(APP_SIGN_ID)" ./app/build.sh

dmg: sign ## Build signed DMG
	@SIGN_IDENTITY="$(APP_SIGN_ID)" CREATE_DMG=1 DMG_NAME="Claudeme-$(VERSION)" ./app/build.sh
	@echo ""
	@echo "✓ DMG ready: dist/Claudeme-$(VERSION).dmg"

pkg: sign ## Build signed pkg installer
	@test -n "$(PKG_SIGN_ID)" || { echo "No Developer ID Installer certificate found in keychain"; exit 1; }
	@echo "Creating pkg with: $(PKG_SIGN_ID)"
	@mkdir -p dist
	@pkgbuild \
		--root "app/build/$(APP_NAME).app" \
		--identifier "com.stuffbucket.OpenInClaudeCode" \
		--version "$(VERSION)" \
		--install-location "/Applications/$(APP_NAME).app" \
		--sign "$(PKG_SIGN_ID)" \
		"dist/Claudeme-$(VERSION).pkg"
	@echo ""
	@echo "✓ PKG ready: dist/Claudeme-$(VERSION).pkg"

install: build ## Build and install to /Applications
	@echo "Installing to /Applications..."
	@cp -R 'app/build/$(APP_NAME).app' /Applications/
	@echo "✓ Installed to /Applications"
	@echo ""
	@echo "To add to Finder toolbar:"
	@echo "  Hold ⌘ and drag the app from /Applications to the toolbar"

uninstall: ## Remove from /Applications
	@rm -rf '/Applications/$(APP_NAME).app'
	@echo "✓ Uninstalled"

release: ## Create a release (push a tag: make release TAG=v1.0.0)
	@test -n "$(TAG)" || { echo "Usage: make release TAG=v1.0.0"; exit 1; }
	@echo "Creating release $(TAG)..."
	@git tag -a $(TAG) -m "Release $(TAG)" 2>/dev/null || true
	@git push origin $(TAG)
	@echo ""
	@echo "✓ Tag $(TAG) pushed. The self-hosted runner will build, sign, notarize, and publish the release."

clean: ## Clean build artifacts
	@rm -rf app/build dist
	@rm -f checksums.txt
	@echo "✓ Cleaned"
