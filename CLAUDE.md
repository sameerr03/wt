# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`wt` is a shell-based Git worktree manager for Claude Code workflows. It creates isolated worktrees per feature, automates dependency installation, integrates with Claude Code, and handles PR merging/cleanup. Pure zsh — no build system, no tests, no linting.

## Architecture

Single-file application (`wt.sh`, ~510 lines) sourced into the user's shell. All functions are defined in this file:

- `wt()` — command dispatcher that routes to `_wt_<command>()` handlers
- `_wt_detect_context()` — auto-detects project/feature from the current working directory by matching against `WT_PROJECTS` paths and `WORKTREE_BASE` layout
- `_wt_new()` — creates worktree, copies `.env`, runs install command, optionally launches Claude
- `_wt_cd()` — jumps into existing worktree or creates one from an existing branch
- `_wt_rm()` — removes worktree and optionally deletes the branch
- `_wt_merge()` — merges PR via `gh`, then cleans up worktree and branch
- `_wt_ls()` / `_wt_ls_project()` — lists worktrees with PR status via `gh`
- `_wt_get_install_cmd()` — resolves package manager per project (checks `WT_PKG_MANAGER`, falls back to lockfile detection)

Configuration lives in `config.sh` (gitignored, user-specific). `config.template.sh` is the reference template. Key config: `WT_PROJECTS` associative array (project→repo path), `WORKTREE_BASE`, `WT_PKG_MANAGER`.

## Dependencies

Requires: zsh, git, GitHub CLI (`gh`), jq. No package manager — pure shell.

## Shell Conventions

- All internal functions are prefixed with `_wt_` to avoid namespace collisions
- Uses zsh-specific features: associative arrays (`typeset -A`), `local` variables, `${(k)}` parameter expansion
- Error output goes to stderr; status messages use color codes
- Functions return non-zero on error with early returns
