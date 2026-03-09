.PHONY: help build test test-v test-cover lint fmt vet vulncheck clean deps verify install-requirements setup check-go

export GOTOOLCHAIN=auto
SHELL := /bin/bash

ESC    := $(shell printf '\033')
BOLD   := $(ESC)[1m
CYAN   := $(ESC)[36m
GREEN  := $(ESC)[32m
YELLOW := $(ESC)[33m
RED    := $(ESC)[31m
GREY   := $(ESC)[90m
RESET  := $(ESC)[0m

GO_REQUIRED := $(shell awk '/^go /{print $$2}' go.mod)

help:
	@printf "\n$(BOLD)vmware-content-library-core$(RESET)\n"
	@printf "$(CYAN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)\n"
	@printf "\n$(BOLD)  Development$(RESET)\n"
	@printf "    $(GREEN)make build$(RESET)         		Compile check (all packages)\n"
	@printf "    $(GREEN)make fmt$(RESET)           		Format source files\n"
	@printf "    $(GREEN)make vet$(RESET)           		Run go vet\n"
	@printf "    $(GREEN)make lint$(RESET)          		Run golangci-lint (if installed)\n"
	@printf "\n$(BOLD)  Testing$(RESET)\n"
	@printf "    $(GREEN)make test$(RESET)          		Run all tests\n"
	@printf "    $(GREEN)make test-v$(RESET)        		Run tests with verbose output\n"
	@printf "    $(GREEN)make test-cover$(RESET)    		Run tests + generate HTML coverage report\n"
	@printf "    $(GREEN)make vulncheck$(RESET)     		Run govulncheck (if installed)\n"
	@printf "\n$(BOLD)  Setup$(RESET)\n"
	@printf "    $(GREEN)make install-requirements$(RESET)  Install required tools\n"
	@printf "    $(GREEN)make setup$(RESET)               Install pre-commit hook\n"
	@printf "\n$(BOLD)  Maintenance$(RESET)\n"
	@printf "    $(GREEN)make clean$(RESET)         		Remove build artifacts and test cache\n"
	@printf "    $(GREEN)make deps$(RESET)          		Download + tidy dependencies\n"
	@printf "    $(GREEN)make verify$(RESET)        		Verify dependency checksums\n"
	@printf "\n$(CYAN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)\n\n"

check-go:
	@{ \
		LOCAL_VER=$$(GOTOOLCHAIN=local go env GOVERSION 2>/dev/null | sed 's/^go//' || echo "unknown"); \
		REQUIRED="$(GO_REQUIRED)"; \
		if [ "$$LOCAL_VER" = "unknown" ]; then \
			printf "$(YELLOW)Go not found in PATH.$(RESET)\n"; \
			printf "  Run: $(GREEN)make install-requirements$(RESET)\n\n"; \
			exit 1; \
		fi; \
		LOWEST=$$(printf '%s\n%s\n' "$$REQUIRED" "$$LOCAL_VER" | sort -V | head -n1); \
		if [ "$$LOWEST" != "$$REQUIRED" ]; then \
			printf "$(YELLOW)Local Go too old (local: $$LOCAL_VER, required: $$REQUIRED).$(RESET)\n"; \
			printf "  Run: $(GREEN)make install-requirements$(RESET)\n\n"; \
			exit 1; \
		fi; \
	}

build: check-go
	@printf "$(CYAN)Compiling all packages...$(RESET)\n"
	@go build ./...
	@printf "$(GREEN)✓ All packages compile OK$(RESET)\n"

test: check-go
	@printf "$(CYAN)Running tests...$(RESET)\n"
	@set -o pipefail; go test ./... 2>&1 | sed \
		-e 's|^ok |$(GREEN)ok$(RESET) |g' \
		-e 's|^FAIL|$(RED)FAIL$(RESET)|g' \
		-e 's|^?|$(GREY)?|g' \
		-e 's|\[no test files\]|$(GREY)[no test files]$(RESET)|g'

test-v: check-go
	@printf "$(CYAN)Running tests (verbose)...$(RESET)\n"
	@set -o pipefail; go test -v ./... 2>&1 | sed \
		-e 's|^ok |$(GREEN)ok$(RESET) |g' \
		-e 's|^FAIL|$(RED)FAIL$(RESET)|g' \
		-e 's|^PASS$$|$(GREEN)PASS$(RESET)|g' \
		-e 's|^--- PASS|$(GREEN)--- PASS$(RESET)|g' \
		-e 's|^--- FAIL|$(RED)--- FAIL$(RESET)|g' \
		-e 's|^=== RUN|$(GREY)=== RUN$(RESET)|g'

test-cover: check-go
	@printf "$(CYAN)Running tests with coverage...$(RESET)\n"
	@mkdir -p tmp
	@set -o pipefail; \
	PKGS=$$(go list ./...); \
	GOCOVERDIR= go test -coverprofile=tmp/coverage.out $$PKGS 2>&1 | sed \
		-e 's|^ok |$(GREEN)ok$(RESET) |g' \
		-e 's|^FAIL|$(RED)FAIL$(RESET)|g' \
		-e 's|^?|$(GREY)?|g' \
		-e 's|\[no test files\]|$(GREY)[no test files]$(RESET)|g'; \
	go tool cover -html=tmp/coverage.out -o tmp/coverage.html
	@printf "$(GREEN)✓ Coverage report: tmp/coverage.html$(RESET)\n"

GOLANGCI_LINT := $(shell command -v golangci-lint 2>/dev/null)
ifeq ($(GOLANGCI_LINT),)
GOLANGCI_LINT := $(shell GOPATH=$$(go env GOPATH); [ -x "$$GOPATH/bin/golangci-lint" ] && echo "$$GOPATH/bin/golangci-lint")
endif

lint:
	@{ \
		if [ -z "$(GOLANGCI_LINT)" ]; then \
			printf "$(YELLOW)golangci-lint not installed.$(RESET)\n"; \
			printf "  Run: $(GREEN)make install-requirements$(RESET)\n\n"; \
			exit 0; \
		fi; \
	}; \
	printf "$(CYAN)Running golangci-lint...$(RESET)\n"; \
	"$(GOLANGCI_LINT)" run ./...

fmt:
	@printf "$(CYAN)Formatting code...$(RESET)\n"
	@go fmt ./...
	@printf "$(GREEN)✓ Done$(RESET)\n"

GO_BIN_DIR := $(shell [ -x "/usr/local/go/bin/go" ] && echo "/usr/local/go/bin")
GOVULNCHECK := $(shell command -v govulncheck 2>/dev/null)
vulncheck:
	@{ \
		if [ -z "$(GOVULNCHECK)" ]; then \
			printf "$(YELLOW)govulncheck not installed.$(RESET)\n"; \
			printf "  Run: $(GREEN)make install-requirements$(RESET)\n\n"; \
			exit 0; \
		fi; \
	}; \
	printf "$(CYAN)Running govulncheck...$(RESET)\n"; \
	PATH="$(GO_BIN_DIR):$$PATH" GOTOOLCHAIN=auto "$(GOVULNCHECK)" ./...

vet: check-go
	@printf "$(CYAN)Running go vet...$(RESET)\n"
	@go vet ./...
	@printf "$(GREEN)✓ Done$(RESET)\n"

clean:
	@printf "$(CYAN)Cleaning build artifacts...$(RESET)\n"
	@rm -f tmp/coverage.out tmp/coverage.html
	@go clean -testcache
	@printf "$(GREEN)✓ Clean complete$(RESET)\n"

deps: check-go
	@printf "$(CYAN)Updating dependencies...$(RESET)\n"
	@go mod download
	@go mod tidy
	@printf "$(GREEN)✓ Dependencies updated$(RESET)\n"

verify: check-go
	@printf "$(CYAN)Verifying dependencies...$(RESET)\n"
	@go mod verify
	@printf "$(GREEN)✓ All dependencies verified$(RESET)\n"

install-requirements:
	@bash scripts/install-requirements.sh

REPO_STANDARDS_KIT ?= ../repo-standards-kit

setup:
	@mkdir -p .git/hooks
	@if [ -f "$(REPO_STANDARDS_KIT)/templates/common/hooks/pre-commit" ]; then \
		cp "$(REPO_STANDARDS_KIT)/templates/common/hooks/pre-commit" .git/hooks/pre-commit; \
		chmod +x .git/hooks/pre-commit; \
		printf "$(GREEN)✓ pre-commit hook installed$(RESET)\n"; \
	else \
		printf "$(YELLOW)Hook not found at $(REPO_STANDARDS_KIT)/templates/common/hooks/pre-commit$(RESET)\n"; \
		printf "$(YELLOW)Set REPO_STANDARDS_KIT=<path> to override.$(RESET)\n"; \
		exit 1; \
	fi
