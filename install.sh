#!/usr/bin/env bash
# Installs this repo as a Claude Code skill at ~/.claude/skills/hpc-slurm/,
# invokable as /hpc-slurm in any Claude Code session.
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST=${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}/hpc-slurm

mkdir -p "$DEST"
cp "$SRC/SKILL.md" "$DEST/SKILL.md"
cp -r "$SRC/templates" "$DEST/templates"

echo "Installed hpc-slurm skill to $DEST"
echo "Start a new Claude Code session (or run /hpc-slurm) to use it."
