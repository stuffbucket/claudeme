SHELL := /bin/bash

.DEFAULT_GOAL := help

APP_NAME := Open in Claude Code
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

.PHONY: help setup build install uninstall release clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## First-time setup for contributors
	@echo "Setting up development environment..."
	@git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true
	@echo "✓ Setup complete"

build: ## Build the macOS app
	@./app/build.sh

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
	@rm -rf app/build
	@rm -f *.zip checksums.txt
	@echo "✓ Cleaned"
