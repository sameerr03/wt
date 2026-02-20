# wt

Git worktree manager for Claude Code workflows. Create isolated worktrees per feature, work with Claude, merge PRs, and clean up — all in one tool.

## Setup

1. Clone the repo:
   ```bash
   git clone https://github.com/sameerr03/wt.git ~/.wt
   ```

2. Add to your `.zshrc`:
   ```bash
   source ~/.wt/wt.sh
   ```

3. Copy the template and edit your config:
   ```bash
   cp ~/.wt/config.template.sh ~/.wt/config.sh
   ```

4. Edit `config.sh` to register your projects:
   ```bash
   declare -A WT_PROJECTS=(
     [myapp]="/path/to/myapp"
   )
   ```

## Commands

### `wt new <project> <feature> [--base <branch>]`

Creates a worktree, copies `.env` files, installs dependencies, and launches Claude Code.

```bash
wt new carousel fix-slider
wt new carousel fix-slider --base dev
```

### `wt merge <project> <feature> [--squash|--rebase]`

Merges the PR, removes the worktree, deletes the branch (local + remote), and pulls main. Defaults to `--squash`.

```bash
wt merge carousel fix-slider
wt merge carousel fix-slider --rebase
```

### `wt rm <project> <feature> [--delete-branch]`

Removes a worktree without merging. Optionally deletes the branch.

```bash
wt rm carousel fix-slider
wt rm carousel fix-slider --delete-branch
```

### `wt ls [project]`

Lists active worktrees with PR status (PR number, review state, checks).

```
carousel:
  fix-slider  (/Users/sameer/Code/worktrees/carousel/fix-slider)
    PR #42 — ✓ approved, ✓ CHECKS PASS
```

### `wt help`

Shows usage and examples.

## Configuration

All config lives in `config.sh`:

| Variable | Purpose | Default |
|----------|---------|---------|
| `WT_PROJECTS` | Map of project name → repo path | — |
| `WT_PKG_MANAGER` | Per-project package manager override | `npm` |
| `WORKTREE_BASE` | Where worktrees are created | `/Users/sameer/Code/worktrees` |
| `DEFAULT_BASE_BRANCH` | Branch to base new worktrees on | `main` |
| `DEFAULT_INSTALL_CMD` | Default install command | `npm install` |

## Requirements

- `zsh`
- `git`
- [`gh`](https://cli.github.com/) (GitHub CLI) — for `merge` and `ls` PR status
- [`jq`](https://jqlang.github.io/jq/) — for parsing PR status
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — launched automatically on `wt new`
