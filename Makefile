SHELL := /bin/bash

.DEFAULT_GOAL := help

APP_NAME := claudeme
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

.PHONY: help setup check test release clean

help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "}; /^[a-zA-Z0-9_.-]+:.*## / {printf "  %-12s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## First-time setup for contributors
	@echo "Setting up development environment..."
	@git config core.hooksPath .githooks
	@chmod +x .githooks/* 2>/dev/null || true
	@chmod +x bin/claudeme
	@echo "✓ Setup complete"

check: ## Run checks (shellcheck)
	@echo "Checking shell script..."
	@bash -n bin/claudeme
	@command -v shellcheck >/dev/null 2>&1 && shellcheck bin/claudeme || echo "shellcheck not installed, skipping"
	@echo "✓ All checks passed"

test: ## Test the claudeme script
	@echo "Testing claudeme..."
	@./bin/claudeme --help >/dev/null
	@echo "✓ Tests passed"

install-local: ## Install locally (for testing)
	@echo "Installing locally..."
	@mkdir -p /usr/local/bin
	@cp bin/claudeme /usr/local/bin/claudeme
	@chmod +x /usr/local/bin/claudeme
	@echo "✓ Installed to /usr/local/bin"
	@echo "Run: claudeme setup"

uninstall-local: ## Uninstall local installation
	@rm -f /usr/local/bin/claudeme
	@echo "✓ Uninstalled"

release: ## Create and publish a release (requires TAG=v1.0.0)
	@test -n "$(TAG)" || { echo "Usage: make release TAG=v1.0.0"; exit 1; }
	@command -v gh >/dev/null 2>&1 || { echo "Install: brew install gh"; exit 1; }
	@echo "Creating release $(TAG)..."
	@git tag -a $(TAG) -m "Release $(TAG)" 2>/dev/null || true
	@git push origin $(TAG)
	@echo ""
	@echo "Release $(TAG) tag pushed. GitHub Action will create the release."

clean: ## Clean build artifacts
	@rm -f *.tar.gz checksums.txt
	@echo "✓ Cleaned"
