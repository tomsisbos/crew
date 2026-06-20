#!/usr/bin/env bash
#
# install.sh — put crew on your PATH and lay down a default config.
#
# Symlinks bin/crew, bin/crew-bridge and bin/crew-watch into ~/.local/bin (override with
# CREW_BIN_DIR), copies crew.conf.example to ~/.config/crew/crew.conf if you don't have one
# yet, and registers the crew-watch login service so worktrees you create in herdr become
# wired agents automatically. Idempotent: safe to re-run.
#
# Flags / env:
#   --no-service  (or CREW_NO_SERVICE=1)  skip registering the crew-watch login service.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${CREW_BIN_DIR:-$HOME/.local/bin}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/crew"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/crew"
AGMSG_CMD="${AGMSG_CMD:-agmsg}"

NO_SERVICE="${CREW_NO_SERVICE:-0}"
for arg in "$@"; do
  case "$arg" in
    --no-service) NO_SERVICE=1 ;;
    *) printf 'crew install: unknown argument: %s\n' "$arg" >&2; exit 1 ;;
  esac
done

ok()   { printf '  \033[32m+\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mcrew install: %s\033[0m\n' "$*" >&2; exit 1; }

echo "crew — installing"
echo "─────────────────"

# --- dependency checks (fail fast, no silent fallbacks) ---
missing=0
for dep in herdr git jq sqlite3; do
  if command -v "$dep" >/dev/null 2>&1; then ok "found $dep"; else warn "missing $dep"; missing=1; fi
done
if [ -d "$HOME/.agents/skills/$AGMSG_CMD/scripts" ]; then
  ok "found agmsg ($AGMSG_CMD)"
else
  warn "missing agmsg at ~/.agents/skills/$AGMSG_CMD/scripts"; missing=1
fi
if [ "$missing" -ne 0 ]; then
  cat >&2 <<EOF

Install the missing prerequisites first:
  herdr   — https://herdr.dev/docs/install/   (e.g. brew install herdr)
  agmsg   — https://agmsg.cc/  (git clone https://github.com/fujibee/agmsg && cd agmsg && ./install.sh)
  jq / sqlite3 / git — your package manager (sqlite3 + git ship with macOS)
EOF
  die "missing prerequisites"
fi

# --- symlink binaries ---
mkdir -p "$BIN_DIR"
for b in crew crew-bridge crew-watch; do
  ln -sf "$SRC_DIR/bin/$b" "$BIN_DIR/$b"
  ok "linked $BIN_DIR/$b"
done
chmod +x "$SRC_DIR/bin/crew" "$SRC_DIR/bin/crew-bridge" "$SRC_DIR/bin/crew-watch"

# --- config + state dirs ---
mkdir -p "$CONF_DIR" "$STATE_DIR"
if [ -f "$CONF_DIR/crew.conf" ]; then
  ok "config exists ($CONF_DIR/crew.conf) — left untouched"
else
  cp "$SRC_DIR/crew.conf.example" "$CONF_DIR/crew.conf"
  ok "wrote default config ($CONF_DIR/crew.conf)"
fi

# --- PATH check ---
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on your PATH — add it, e.g.:"
     warn "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && exec zsh" ;;
esac

# --- crew-watch login service (auto-adopt herdr worktrees) ---
if [ "$NO_SERVICE" = "1" ]; then
  warn "skipping crew-watch service (--no-service) — start it yourself with 'crew watch'"
else
  if "$BIN_DIR/crew" watch service install; then
    ok "registered crew-watch login service"
  else
    warn "could not register crew-watch service — start it yourself with 'crew watch'"
  fi
fi

cat <<EOF

Done. Next steps:
  1. Wire herdr's Claude state detection (one time):
       herdr integration install claude
  2. Start herdr (server + UI):
       herdr
  3. Spawn agents either way — both end up fully wired:
       • In herdr: menu → New worktree (crew-watch adopts it automatically), or
       • From a terminal: crew new my-feature "draft the API layer"

See the README for the status / messaging / retire cheatsheet.
EOF
