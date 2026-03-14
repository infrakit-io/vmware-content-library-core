#!/usr/bin/env bash
set -euo pipefail

BOLD="\033[1m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

GO_VERSION="1.26.1"

info()    { printf "  ${CYAN}%s${RESET}\n" "$1"; }
success() { printf "  ${GREEN}✓ %s${RESET}\n" "$1"; }
warn()    { printf "  ${YELLOW}⚠ %s${RESET}\n" "$1"; }

need_sudo() {
  if [ "$EUID" -ne 0 ]; then
    echo sudo
  fi
}

SUDO=$(need_sudo)
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) GO_ARCH="amd64" ;;
  arm64|aarch64) GO_ARCH="arm64" ;;
  *) GO_ARCH="amd64" ;;
esac

printf "\n${BOLD}vmware-content-library-core — install-requirements${RESET}\n"
printf "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

CURRENT_GO_LOCAL=$(GOTOOLCHAIN=local go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | sed 's/^go//' || echo "none")
if [ "$CURRENT_GO_LOCAL" != "$GO_VERSION" ]; then
  info "Installing Go ${GO_VERSION} (current local: ${CURRENT_GO_LOCAL})..."
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  TARBALL="go${GO_VERSION}.${OS}-${GO_ARCH}.tar.gz"
  URL="https://go.dev/dl/${TARBALL}"
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  curl -sfL "$URL" -o "$TMPDIR/$TARBALL"
  $SUDO rm -rf /usr/local/go
  $SUDO tar -C /usr/local -xzf "$TMPDIR/$TARBALL"
  success "Go ${GO_VERSION} installed"
else
  success "Go ${GO_VERSION} already installed"
fi

export PATH=$PATH:/usr/local/go/bin:$(go env GOPATH)/bin

if ! command -v golangci-lint >/dev/null 2>&1; then
  info "Installing golangci-lint..."
  curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
    | sh -s -- -b "$(go env GOPATH)/bin" latest
  success "golangci-lint installed"
else
  success "golangci-lint already installed"
fi

if ! command -v govulncheck >/dev/null 2>&1; then
  info "Installing govulncheck..."
  GOBIN="$(go env GOPATH)/bin" GOTOOLCHAIN=local go install golang.org/x/vuln/cmd/govulncheck@latest
  success "govulncheck installed"
else
  success "govulncheck already installed"
fi

if ! echo "$PATH" | grep -q "$(go env GOPATH)/bin"; then
  warn "Consider adding to PATH: export PATH=\$PATH:$(go env GOPATH)/bin"
fi

printf "${GREEN}✓ All requirements installed${RESET}\n\n"
