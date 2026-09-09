#!/usr/bin/env bash
# Installs this repo as a Claude Code skill at ~/.claude/skills/neu-hpc/,
# invokable as /neu-hpc in any Claude Code session.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST=${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/neu-hpc

# Remove the pre-rename skill directory if this machine has it.
OLD=${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/hpc-slurm
if [ -d "$OLD" ]; then
  rm -rf "$OLD"
  echo "Removed superseded skill at $OLD"
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$DEST/SKILL.md"
cp -r "$SRC/templates" "$DEST/templates"
[ -d "$SRC/reference" ] && cp -r "$SRC/reference" "$DEST/reference"

echo "Installed the neu-hpc skill to $DEST"
echo "Start a new Claude Code session, then type /neu-hpc (or just ask an Explorer/Slurm question)."
