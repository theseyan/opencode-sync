#!/usr/bin/env bash
set -euo pipefail

REPO="theseyan/opencode-sync"
BRANCH="${BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"

die() { echo "error: $*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"

mkdir -p "$INSTALL_DIR"

if [[ -f "$(dirname "$0")/opencode-sync" && "$(basename "$0")" == "install.sh" ]]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  cp "$script_dir/opencode-sync" "$INSTALL_DIR/opencode-sync"
else
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW/opencode-sync" -o "$INSTALL_DIR/opencode-sync"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_DIR/opencode-sync" "$RAW/opencode-sync"
  else
    die "curl or wget is required to download opencode-sync"
  fi
fi

chmod +x "$INSTALL_DIR/opencode-sync"

case ":${PATH}:" in
  *":${INSTALL_DIR}:"*) ;;
  *)
    echo "note: add $INSTALL_DIR to your PATH:"
    echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac

echo "installed opencode-sync to $INSTALL_DIR/opencode-sync"
