#!/usr/bin/env bash
# install.sh — 트리거 스킬들을 ~/.claude/skills/, ~/.agents/skills/, ~/.gemini/config/plugins/tayaee-autosdlc/skills/로 symlink 설치 (idempotent).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$REPO_ROOT/skills"
BIN_DIR="$REPO_ROOT/bin"

HOME_DIR="${HOME:-$(getent passwd "$(id -u)" | cut -d: -f6 2>/dev/null || echo ~)}"

CLAUDE_SKILLS="$HOME_DIR/.claude/skills"
AGENTS_SKILLS="$HOME_DIR/.agents/skills"
GEMINI_SKILLS="$HOME_DIR/.gemini/config/plugins/tayaee-autosdlc/skills"
CLAUDE_BIN="$HOME_DIR/.claude/bin"

mkdir -p "$CLAUDE_SKILLS" "$AGENTS_SKILLS" "$GEMINI_SKILLS" "$CLAUDE_BIN"

# Obsolete skills cleanup
OBSOLETE_SKILLS=(autoqa autodev autofix autoqafix acpd autotddreview)
for obs in "${OBSOLETE_SKILLS[@]}"; do
    rm -rf "$CLAUDE_SKILLS/$obs" "$AGENTS_SKILLS/$obs" "$GEMINI_SKILLS/$obs"
done

ACTIVE_SKILLS=(aacp aacpd autotdd autotddreviewfix tdd2)
installed=0

for skill in "${ACTIVE_SKILLS[@]}"; do
    src="$SRC_DIR/$skill"
    if [ ! -d "$src" ]; then
        echo "WARN: $src 없음 — 건너뜀" >&2
        continue
    fi

    for target_dir in "$CLAUDE_SKILLS" "$AGENTS_SKILLS" "$GEMINI_SKILLS"; do
        dst="$target_dir/$skill"
        if [ -L "$dst" ] || [ -e "$dst" ]; then
            rm -rf "$dst"
        fi
        ln -s "$src" "$dst"
        installed=$((installed + 1))
    done
done

# Binaries symlink
for b in "$BIN_DIR"/*; do
    [ -e "$b" ] || continue
    base="$(basename "$b")"
    dst="$CLAUDE_BIN/$base"
    ln -sfn "$b" "$dst"
done

echo "—"
echo "install 요약: 스킬 symlink $installed건 완료 (~/.claude/skills, ~/.agents/skills, ~/.gemini/config/plugins/tayaee-autosdlc/skills 및 ~/.claude/bin)"
exit 0