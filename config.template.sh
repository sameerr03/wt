#!/usr/bin/env zsh

# Project name → main repo path
declare -A WT_PROJECTS=(
  # [myapp]="/path/to/myapp"
  # [backend]="/path/to/backend"
)

# Per-project package manager overrides (default is npm)
declare -A WT_PKG_MANAGER=(
  # [myapp]="bun"
  # [backend]="pnpm"
)

WORKTREE_BASE="$HOME/Code/worktrees"
DEFAULT_BASE_BRANCH="main"
DEFAULT_INSTALL_CMD="npm install"
