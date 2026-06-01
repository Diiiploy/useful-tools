#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# i3-quickphrase validation helpers — sourced by bin/i3-quickphrase
#
# Functions:
#   validate_phrase_name <name>   — name must match ^[a-z][a-z0-9_-]*$
#   validate_phrase_file <path>   — regular file, owned by us, ASCII-only

validate_phrase_name() {
  local name="${1:-}"
  if ! [[ "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    echo "validate: invalid phrase name '$name' (must match ^[a-z][a-z0-9_-]*\$)" >&2
    return 1
  fi
  return 0
}

validate_phrase_file() {
  local f="${1:-}"
  if [[ -z "$f" ]]; then
    echo "validate: no file path given" >&2
    return 1
  fi
  if [[ ! -e "$f" ]]; then
    echo "validate: file does not exist: $f" >&2
    return 1
  fi
  if [[ -L "$f" ]]; then
    echo "validate: symlinks rejected: $f" >&2
    return 1
  fi
  if [[ ! -f "$f" ]]; then
    echo "validate: not a regular file: $f" >&2
    return 1
  fi
  if [[ "$(stat -c %u "$f")" != "$(id -u)" ]]; then
    echo "validate: not owned by current user: $f" >&2
    return 1
  fi
  if [[ ! -r "$f" ]]; then
    echo "validate: unreadable: $f" >&2
    return 1
  fi
  # Allowlist: printable ASCII (0x20-0x7e) + TAB (0x09) + LF (0x0a)
  # Reject everything else, including ANSI escapes, OSC sequences,
  # bidi controls, zero-width characters, and high bytes.
  if LC_ALL=C grep -q -P '[\x00-\x08\x0b-\x1f\x7f-\xff]' "$f"; then
    echo "validate: contains non-printable bytes (rejected for safety): $f" >&2
    return 1
  fi
  return 0
}
