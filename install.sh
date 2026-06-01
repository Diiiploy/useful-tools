#!/usr/bin/env bash
# install.sh — symlink the executable tools in this repo into ~/.local/bin.
#
# Only root-level executable scripts (a file with the +x bit and a "#!"
# shebang) are linked. These are skipped:
#   - non-executables (README.md, LICENSE, *.html)
#   - subdirectories (claude-code/, i3-quickphrase/)
#   - this installer itself
#
# i3-quickphrase is a bundled source backup with its own installer — run
# i3-quickphrase/install.sh to set that one up.
#
# Usage:
#   ./install.sh           Symlink tools into ~/.local/bin
#   ./install.sh -n        Dry run — print what would happen, change nothing
#   ./install.sh -f        Overwrite existing files/symlinks at the destination
#   ./install.sh -d DIR    Install into DIR instead of ~/.local/bin
#   ./install.sh -h        Show this help

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DEST="${HOME}/.local/bin"
DRY_RUN=0
FORCE=0

usage() {
    sed -n '2,24p' "$REPO_DIR/install.sh" | sed 's/^# \{0,1\}//'
}

while getopts ':nfd:h' opt; do
    case "$opt" in
        n) DRY_RUN=1 ;;
        f) FORCE=1 ;;
        d) DEST="$OPTARG" ;;
        h) usage; exit 0 ;;
        :) echo "Error: -$OPTARG needs an argument" >&2; exit 2 ;;
        \?) echo "Error: unknown option -$OPTARG" >&2; exit 2 ;;
    esac
done

self="$(basename "${BASH_SOURCE[0]}")"
linked=0 skipped=0 already=0

[[ "$DRY_RUN" -eq 1 ]] && echo "(dry run — no changes will be made)"
[[ "$DRY_RUN" -eq 1 ]] || mkdir -p "$DEST"

for path in "$REPO_DIR"/*; do
    name="$(basename "$path")"

    [[ -f "$path" ]] || continue                       # skip directories
    [[ "$name" == "$self" ]] && continue               # skip this installer
    [[ -x "$path" ]] || continue                       # executables only
    [[ "$(head -c2 "$path" 2>/dev/null)" == '#!' ]] || continue   # needs a shebang

    target="$DEST/$name"

    if [[ -L "$target" || -e "$target" ]]; then
        if [[ -L "$target" && "$(readlink -f "$target")" == "$path" ]]; then
            echo "= $name (already linked)"
            already=$((already + 1))
            continue
        fi
        if [[ "$FORCE" -eq 1 ]]; then
            if [[ "$DRY_RUN" -eq 1 ]]; then
                echo "~ $name (would overwrite $target)"
            else
                ln -sfn "$path" "$target"
                echo "~ $name (overwritten)"
                linked=$((linked + 1))
            fi
        else
            echo "! $name (exists at $target — use -f to overwrite)"
            skipped=$((skipped + 1))
        fi
        continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "+ $name (would link -> $target)"
    else
        ln -s "$path" "$target"
        echo "+ $name"
        linked=$((linked + 1))
    fi
done

echo "---"
echo "linked=$linked  already=$already  skipped=$skipped  dest=$DEST"

case ":${PATH}:" in
    *":$DEST:"*) ;;
    *) echo "Note: $DEST is not on your PATH — add it to use these as bare commands." ;;
esac

cat <<EOF

Optional extras (not symlinked — place manually if you want them):
  md2pdf stylesheet:   cp "$REPO_DIR/md2pdf-style.html" ~/.local/share/pandoc/
  Claude Code /dlmusic: ln -s "$REPO_DIR/claude-code/dlmusic.md" ~/.claude/commands/dlmusic.md
  i3-quickphrase:       run "$REPO_DIR/i3-quickphrase/install.sh"
EOF
