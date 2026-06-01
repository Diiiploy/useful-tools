#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# i3-quickphrase uninstaller — symmetric, surgical, repo untouched.

set -euo pipefail

PROG="i3-quickphrase"

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "$PROG: refusing to run as root." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LOCAL_BIN="${HOME}/.local/bin/i3-quickphrase"
I3_CONFIG="${HOME}/.config/i3/config"
I3_DROPIN="${HOME}/.config/i3/config.d/i3-quickphrase.conf"

echo "==> $PROG uninstaller"
echo "    Repo: $REPO_ROOT"
echo

# ---- remove binary symlink (only if it points at this repo) ----
if [[ -L "$LOCAL_BIN" ]]; then
  target="$(readlink -f "$LOCAL_BIN" 2>/dev/null || true)"
  if [[ "$target" == "$REPO_ROOT/bin/i3-quickphrase" ]]; then
    rm -f "$LOCAL_BIN"
    echo "    Removed symlink: $LOCAL_BIN"
  else
    echo "    Skipped: $LOCAL_BIN points elsewhere ($target)"
  fi
fi

# ---- remove i3 dropin symlink (only if it points at this repo) ----
if [[ -L "$I3_DROPIN" ]]; then
  target="$(readlink -f "$I3_DROPIN" 2>/dev/null || true)"
  if [[ "$target" == "$REPO_ROOT/dist/i3-quickphrase.conf" ]]; then
    rm -f "$I3_DROPIN"
    echo "    Removed symlink: $I3_DROPIN"
  else
    echo "    Skipped: $I3_DROPIN points elsewhere ($target)"
  fi
fi

# ---- remove BEGIN/END block from main i3 config ----
if [[ -f "$I3_CONFIG" ]] && grep -qF "BEGIN i3-quickphrase" "$I3_CONFIG"; then
  echo "    Removing include block from $I3_CONFIG"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  sed '/# BEGIN i3-quickphrase/,/# END i3-quickphrase/d' "$I3_CONFIG" > "$tmp"
  if i3 -C -c "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$I3_CONFIG"
    trap - EXIT
    echo "    Validated and removed."
  else
    echo "    ERROR: i3 -C validation failed after removal. No changes made." >&2
    exit 1
  fi
fi

# ---- reload i3 ----
i3-msg reload >/dev/null 2>&1 || true

echo
echo "✓ Uninstalled."
echo "  The repo at $REPO_ROOT is untouched."
echo "  Remove it manually if you no longer need it."
