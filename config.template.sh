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
WT_CLI_AGENT="codex"

# Prompt template for wt issue — used when creating a worktree from a GitHub issue.
# Placeholders: {{number}}, {{title}}, {{labels}}, {{body}}
# The prompt is designed to start a discuss-then-plan workflow with your coding agent.
WT_ISSUE_PROMPT='You are working on a GitHub issue in this repository.

## Issue #{{number}}: {{title}}

**Labels:** {{labels}}

---

{{body}}

---

Before writing any code, I want you to discuss this issue with me. Follow this approach:

1. **Understand the context** — read the relevant parts of the codebase. Understand the existing architecture, patterns, and constraints before forming opinions.

2. **Interview me** — ask clarifying questions. What are the requirements? What are the constraints? What does success look like? Do not assume — ask me to fill in the gaps. Ask questions one at a time, not all at once.

3. **Evaluate approaches** — once you understand the problem, suggest 2-3 concrete approaches with clear pros and cons. Be opinionated.

4. **Go deep on the chosen direction** — once we agree on an approach, dig into specifics: what files change, what patterns to follow, what edge cases exist.

5. **Transition to planning** — once we are aligned, summarize the decision and create an implementation plan.

Start by reading the codebase to understand the relevant code, then begin the discussion.'
