# wt

Git worktree manager for Claude Code workflows. Create isolated worktrees per feature, work with Claude, merge PRs, and clean up — all in one tool.

## Setup with Claude Code

The easiest way to get started. This assumes you keep all your git repos in a single parent directory (e.g. `~/Code`, `~/Projects`, `~/dev`, etc.).

1. Clone the repo and paste this prompt into Claude Code:

   ```
   I just cloned https://github.com/sameerr03/wt.git to ~/.wt. Set it up for me:
   1. Add `source ~/.wt/wt.sh` to my shell rc file (.zshrc) if it's not already there
   2. Copy ~/.wt/config.template.sh to ~/.wt/config.sh
   3. Look at my git repos in ~/Code (replace with wherever I keep my projects).
      For each repo found, add an entry to the WT_PROJECTS array in ~/.wt/config.sh
      mapping the folder name to its absolute path
   4. Set WORKTREE_BASE to a "worktrees" directory alongside my projects
   5. Check each repo for bun.lockb or pnpm-lock.yaml — if found, add an override
      to WT_PKG_MANAGER with "bun" or "pnpm" respectively
   6. Tell me to run `source ~/.zshrc` when done
   ```

   > **Note:** Replace `~/Code` in the prompt with the actual path to the directory where you keep your projects.

## Manual Setup

If you prefer to set things up yourself:

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

### `wt cd <project> <feature>`

Jumps into a worktree and continues the most recent Claude Code session. If no worktree exists but the branch does (locally or on the remote), it automatically creates the worktree, copies `.env` files, installs dependencies, and resumes the session.

```bash
wt cd carousel fix-slider
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
| `WORKTREE_BASE` | Where worktrees are created | `$HOME/Code/worktrees` |
| `DEFAULT_BASE_BRANCH` | Branch to base new worktrees on | `main` |
| `DEFAULT_INSTALL_CMD` | Default install command | `npm install` |

## Requirements

- `zsh`
- `git`
- [`gh`](https://cli.github.com/) (GitHub CLI) — for `merge` and `ls` PR status
- [`jq`](https://jqlang.github.io/jq/) — for parsing PR status
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — launched automatically on `wt new`
