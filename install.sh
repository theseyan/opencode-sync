#!/usr/bin/env bash
set -euo pipefail

REPO="theseyan/opencode-sync"
BRANCH="${BRANCH:-main}"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.opencode-sync/bin}"
NO_PATH_UPDATE="${NO_PATH_UPDATE:-}"

platform=$(uname -ms)
if [[ ${OS:-} = Windows_NT && "$platform" != MINGW64* ]]; then
  powershell -NoProfile -c "irm ${RAW}/install.ps1 | iex"
  exit $?
fi

die() { echo "error: $*" >&2; exit 1; }
info() { echo "$*"; }

tildify() {
  case "$1" in
    "$HOME"/*) echo "~/${1#"$HOME"/}" ;;
    *) echo "$1" ;;
  esac
}

command -v git >/dev/null 2>&1 || die "git is required"

mkdir -p "$INSTALL_DIR"

script_path="${BASH_SOURCE[0]:-}"
use_local=false
if [[ -n "$script_path" && "$(basename "$script_path")" == "install.sh" ]]; then
  script_dir="$(cd "$(dirname "$script_path")" && pwd)"
  if [[ -f "$script_dir/opencode-sync" ]]; then
    use_local=true
    cp "$script_dir/opencode-sync" "$INSTALL_DIR/opencode-sync"
  fi
fi

if ! $use_local; then
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --progress-bar --output "$INSTALL_DIR/opencode-sync" "$RAW/opencode-sync" ||
      die "failed to download opencode-sync"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_DIR/opencode-sync" "$RAW/opencode-sync" ||
      die "failed to download opencode-sync"
  else
    die "curl or wget is required"
  fi
fi

chmod +x "$INSTALL_DIR/opencode-sync"

path_line="export PATH=\"$(tildify "$INSTALL_DIR"):\$PATH\""

add_path_to_file() {
  local file="$1"
  [[ -w "$file" ]] || return 1
  if grep -qF '.opencode-sync/bin' "$file" 2>/dev/null; then
    return 0
  fi
  {
    echo
    echo "# opencode-sync"
    echo "$path_line"
  } >>"$file"
  info "added $(tildify "$INSTALL_DIR") to PATH in $(tildify "$file")"
  return 0
}

REFRESH_CMD=""

setup_path() {
  local refresh="" configured=false

  case "$(basename "${SHELL:-}")" in
    fish)
      local fish_config="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
      if [[ -w "$fish_config" ]] && ! grep -qF '.opencode-sync/bin' "$fish_config" 2>/dev/null; then
        {
          echo
          echo "# opencode-sync"
          echo "fish_add_path $(tildify "$INSTALL_DIR")"
        } >>"$fish_config"
        info "added $(tildify "$INSTALL_DIR") to PATH in $(tildify "$fish_config")"
        configured=true
        refresh="source $(tildify "$fish_config")"
      elif [[ -w "$fish_config" ]]; then
        configured=true
        refresh="source $(tildify "$fish_config")"
      fi
      ;;
    zsh)
      local zsh_config="${ZDOTDIR:-$HOME}/.zshrc"
      if add_path_to_file "$zsh_config"; then
        configured=true
        refresh="source $(tildify "$zsh_config")"
      fi
      ;;
    bash)
      local bash_config
      for bash_config in \
        "${HOME}/.bash_profile" \
        "${HOME}/.bashrc" \
        "${XDG_CONFIG_HOME:-}/bash_profile" \
        "${XDG_CONFIG_HOME:-}/bashrc"; do
        [[ -n "$bash_config" && -w "$bash_config" ]] || continue
        if add_path_to_file "$bash_config"; then
          configured=true
          refresh="source $(tildify "$bash_config")"
          break
        fi
      done
      ;;
  esac

  if ! $configured; then
    info "add to your shell rc file:"
    info "  $path_line"
    REFRESH_CMD=""
    return
  fi

  REFRESH_CMD="$refresh"
}

info "installed opencode-sync to $(tildify "$INSTALL_DIR/opencode-sync")"

if command -v opencode-sync >/dev/null 2>&1; then
  info "run: opencode-sync init"
  exit 0
fi

if [[ -n "$NO_PATH_UPDATE" ]]; then
  info "add to PATH:"
  info "  $path_line"
  info "then run: opencode-sync init"
  exit 0
fi

setup_path

if [[ -n "${REFRESH_CMD:-}" ]]; then
  info "open a new terminal, or run:"
  info "  $REFRESH_CMD"
elif [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  info "add to PATH:"
  info "  $path_line"
fi

info "then run: opencode-sync init"
