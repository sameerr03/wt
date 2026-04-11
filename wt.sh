#!/usr/bin/env zsh

# Load config
source "$(dirname "${(%):-%x}")/config.sh"

wt() {
  local cmd="$1"
  shift

  case "$cmd" in
    new)    _wt_new "$@" ;;
    issue)  _wt_issue "$@" ;;
    cd)     _wt_cd "$@" ;;
    rm)     _wt_rm "$@" ;;
    merge)  _wt_merge "$@" ;;
    ls)     _wt_ls "$@" ;;
    help)   _wt_help ;;
    *)      _wt_help; return 1 ;;
  esac
}

_wt_help() {
  echo "wt — Git worktree manager for Claude Code workflows"
  echo ""
  echo "Commands:"
  echo "  new   [--base <branch>]        Pick project, name feature, create worktree"
  echo "  issue [project] <issue#>       Create worktree from GitHub issue"
  echo "  cd                             Pick worktree to jump into"
  echo "  rm                             Pick worktree to remove"
  echo "  merge [--squash|--rebase]      Merge current worktree's PR and cleanup"
  echo "  ls    [project]                List worktrees with PR status"
  echo ""
  echo "Requires: fzf (brew install fzf)"
}

# Auto-detect project and feature from current working directory.
# Sets _wt_detected_project and _wt_detected_feature variables.
_wt_detect_context() {
  _wt_detected_project=""
  _wt_detected_feature=""

  # Check if we're inside a worktree: $WORKTREE_BASE/<project>/<feature>/...
  if [[ "$PWD" == "$WORKTREE_BASE"/* ]]; then
    local rel="${PWD#$WORKTREE_BASE/}"
    _wt_detected_project="${rel%%/*}"
    rel="${rel#*/}"
    _wt_detected_feature="${rel%%/*}"
    return
  fi

  # Check if we're inside a main repo directory
  for p in "${(k)WT_PROJECTS[@]}"; do
    if [[ "$PWD" == "${WT_PROJECTS[$p]}"* ]]; then
      _wt_detected_project="$p"
      return
    fi
  done
}

# Strip prefix from branch names containing slashes (e.g. "claude/fix-bug" -> "fix-bug")
_wt_strip_branch_prefix() {
  local branch="$1"
  echo "${branch##*/}"
}

# Get the real branch name from a worktree directory via git
_wt_get_branch() {
  local wt_path="$1"
  git -C "$wt_path" rev-parse --abbrev-ref HEAD 2>/dev/null
}

_wt_get_install_cmd() {
  local project="$1"
  if [[ -n "${WT_PKG_MANAGER[$project]}" ]]; then
    echo "${WT_PKG_MANAGER[$project]} install"
  else
    echo "$DEFAULT_INSTALL_CMD"
  fi
}

_wt_has_fzf() {
  command -v fzf &>/dev/null
}

# Interactive project picker via fzf. Sets the variable named by $1.
_wt_pick_project() {
  if ! _wt_has_fzf; then
    echo "Error: fzf required for interactive project picker (brew install fzf)" >&2
    return 1
  fi
  local _picked
  _picked=$(printf '%s\n' "${(k)WT_PROJECTS[@]}" | fzf --prompt="Project: " --height=~10 --reverse)
  [[ -n "$_picked" ]] && echo "$_picked"
}

# Interactive worktree picker via fzf. Returns "project/feature" to stdout.
_wt_pick_worktree() {
  if ! _wt_has_fzf; then
    echo "Error: fzf required for interactive worktree picker (brew install fzf)" >&2
    return 1
  fi
  local entries=()
  for p in "${(k)WT_PROJECTS[@]}"; do
    local wt_dir="$WORKTREE_BASE/$p"
    [[ -d "$wt_dir" ]] || continue
    for d in "$wt_dir"/*(N/); do
      local name="${d:t}"
      entries+=("$p/$name")
    done
  done
  if [[ ${#entries[@]} -eq 0 ]]; then
    echo "No active worktrees." >&2
    return 1
  fi
  printf '%s\n' "${entries[@]}" | fzf --prompt="Worktree: " --height=~10 --reverse
}

_wt_cd() {
  # Pick a worktree via fzf
  local selection
  selection=$(_wt_pick_worktree) || return 1
  local project="${selection%%/*}"
  local feature="${selection#*/}"

  cd "$WORKTREE_BASE/$project/$feature"

  printf "Launch Claude? [Y/n] "
  local confirm
  read -r confirm
  if [[ "$confirm" != [nN] ]]; then
    claude --continue
  fi
}

_wt_new() {
  local base_branch="$DEFAULT_BASE_BRANCH"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base_branch="$2"; shift 2 ;;
      *)      shift ;;
    esac
  done

  # Pick project (auto-detect or fzf)
  _wt_detect_context
  local project="$_wt_detected_project"
  if [[ -z "$project" ]]; then
    project=$(_wt_pick_project) || return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    return 1
  fi

  # Prompt for feature name
  printf "Feature name: "
  local feature
  read -r feature
  if [[ -z "$feature" ]]; then
    echo "Error: Feature name required"
    return 1
  fi

  local feature_dir="$(_wt_strip_branch_prefix "$feature")"
  local wt_path="$WORKTREE_BASE/$project/$feature_dir"

  if [[ -d "$wt_path" ]]; then
    echo "Error: Worktree already exists at $wt_path"
    return 1
  fi

  # Create project dir under worktrees if needed
  mkdir -p "$WORKTREE_BASE/$project"

  echo "Creating worktree for $project/$feature (base: $base_branch)..."

  # Fetch latest and create branch + worktree
  git -C "$repo_path" fetch origin "$base_branch" 2>/dev/null
  if ! git -C "$repo_path" worktree add -b "$feature" "$wt_path" "origin/$base_branch" 2>/dev/null; then
    # Branch might already exist
    if ! git -C "$repo_path" worktree add "$wt_path" "$feature" 2>/dev/null; then
      echo "Error: Failed to create worktree. Does the branch '$feature' already exist and is checked out elsewhere?"
      return 1
    fi
  fi

  echo "Worktree created at $wt_path"

  # Copy env files
  local env_count=0
  for env_file in "$repo_path"/.env*; do
    if [[ -f "$env_file" ]]; then
      cp "$env_file" "$wt_path/"
      env_count=$((env_count + 1))
    fi
  done
  echo "Copied $env_count env file(s)"

  # Install dependencies
  local install_cmd="$(_wt_get_install_cmd "$project")"
  echo "Running $install_cmd..."
  (cd "$wt_path" && eval "$install_cmd")

  if [[ $? -ne 0 ]]; then
    echo "Warning: $install_cmd failed. You may need to run it manually."
  fi

  echo ""
  echo "Ready! Entering worktree and launching Claude Code..."
  echo "---"

  # cd into worktree and launch claude
  cd "$wt_path"
  claude
}

_wt_issue() {
  local project="" issue_number="" base_branch="$DEFAULT_BASE_BRANCH"

  # Parse args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base)
        base_branch="$2"
        shift 2
        ;;
      *)
        if [[ -z "$project" ]]; then
          project="$1"
        elif [[ -z "$issue_number" ]]; then
          issue_number="$1"
        fi
        shift
        ;;
    esac
  done

  # Auto-detect from current directory
  _wt_detect_context
  if [[ -z "$issue_number" && -n "$project" && -n "$_wt_detected_project" && -z "${WT_PROJECTS[$project]}" ]]; then
    # Single arg given and it's not a known project — treat as issue number
    issue_number="$project"
    project="$_wt_detected_project"
  fi
  [[ -z "$project" ]] && project="$_wt_detected_project"

  if [[ -z "$project" || -z "$issue_number" ]]; then
    echo "Usage: wt issue [project] <issue#> [--base <branch>]"
    echo "  (project can be auto-detected from current directory)"
    return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    echo "Available projects: ${(k)WT_PROJECTS}"
    return 1
  fi

  local remote_url
  remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null)

  # Fetch issue details from GitHub
  echo "Fetching issue #$issue_number..."
  local issue_json
  issue_json=$(gh issue view "$issue_number" --repo "$remote_url" --json title,body,labels 2>/dev/null)

  if [[ $? -ne 0 || -z "$issue_json" ]]; then
    echo "Error: Could not fetch issue #$issue_number from $remote_url"
    return 1
  fi

  local title body labels
  title=$(printf '%s' "$issue_json" | jq -r '.title')
  body=$(printf '%s' "$issue_json" | jq -r '.body')
  labels=$(printf '%s' "$issue_json" | jq -r '[.labels[].name] | join(", ")')
  [[ -z "$labels" ]] && labels="none"

  # Generate a compact branch name from the issue title via Claude
  local feature
  feature=$(claude -p "Generate a concise git branch name (lowercase, hyphens only, no leading/trailing hyphens) that captures the essence of this issue title. Output ONLY the branch name, nothing else: $title" 2>/dev/null)
  # Sanitize in case the model returns unexpected characters
  feature=$(echo "$feature" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

  if [[ -z "$feature" ]]; then
    echo "Error: Could not parse issue title for branch name"
    return 1
  fi

  echo "Issue: #$issue_number — $title"
  echo "Branch: $feature"

  local feature_dir="$(_wt_strip_branch_prefix "$feature")"
  local wt_path="$WORKTREE_BASE/$project/$feature_dir"

  if [[ -d "$wt_path" ]]; then
    echo "Error: Worktree already exists at $wt_path"
    return 1
  fi

  # Create project dir under worktrees if needed
  mkdir -p "$WORKTREE_BASE/$project"

  echo "Creating worktree for $project/$feature (base: $base_branch)..."

  # Fetch latest and create branch + worktree
  git -C "$repo_path" fetch origin "$base_branch" 2>/dev/null
  if ! git -C "$repo_path" worktree add -b "$feature" "$wt_path" "origin/$base_branch" 2>/dev/null; then
    if ! git -C "$repo_path" worktree add "$wt_path" "$feature" 2>/dev/null; then
      echo "Error: Failed to create worktree. Does the branch '$feature' already exist and is checked out elsewhere?"
      return 1
    fi
  fi

  echo "Worktree created at $wt_path"

  # Copy env files
  local env_count=0
  for env_file in "$repo_path"/.env*; do
    if [[ -f "$env_file" ]]; then
      cp "$env_file" "$wt_path/"
      env_count=$((env_count + 1))
    fi
  done
  echo "Copied $env_count env file(s)"

  # Install dependencies
  local install_cmd="$(_wt_get_install_cmd "$project")"
  echo "Running $install_cmd..."
  (cd "$wt_path" && eval "$install_cmd")

  if [[ $? -ne 0 ]]; then
    echo "Warning: $install_cmd failed. You may need to run it manually."
  fi

  # Build the prompt from the template
  local prompt="$WT_ISSUE_PROMPT"
  prompt="${prompt//\{\{number\}\}/$issue_number}"
  prompt="${prompt//\{\{title\}\}/$title}"
  prompt="${prompt//\{\{labels\}\}/$labels}"
  prompt="${prompt//\{\{body\}\}/$body}"

  echo ""
  echo "Ready! Entering worktree and launching Claude Code with issue context..."
  echo "---"

  # cd into worktree and launch claude with issue context
  cd "$wt_path"
  claude "$prompt"
}

_wt_rm() {
  # Pick a worktree via fzf
  local selection
  selection=$(_wt_pick_worktree) || return 1
  local project="${selection%%/*}"
  local feature="${selection#*/}"

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    return 1
  fi

  local wt_path="$WORKTREE_BASE/$project/$feature"

  if [[ ! -d "$wt_path" ]]; then
    echo "Error: No worktree found at $wt_path"
    return 1
  fi

  # Get real branch name from the worktree before removing it
  local branch_name="$(_wt_get_branch "$wt_path")"

  # If we're inside the worktree, move out first
  if [[ "$PWD" == "$wt_path"* ]]; then
    cd "$repo_path"
  fi

  echo "Removing worktree $project/$feature..."
  git -C "$repo_path" worktree remove "$wt_path" --force

  # Clean up the directory if it somehow still exists
  if [[ -d "$wt_path" ]]; then
    rm -rf "$wt_path"
  fi

  printf "Delete branch '$branch_name'? [y/N] "
  local confirm
  read -r confirm

  if [[ "$confirm" == [yY] ]]; then
    echo "Deleting branch '$branch_name'..."
    git -C "$repo_path" branch -D "$branch_name" 2>/dev/null
  fi

  echo "Done."
}

_wt_merge() {
  local merge_strategy="--merge"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash)  merge_strategy="--squash"; shift ;;
      --rebase)  merge_strategy="--rebase"; shift ;;
      --merge)   merge_strategy="--merge"; shift ;;
      *)         shift ;;
    esac
  done

  # Auto-detect from current directory — must be in a worktree
  _wt_detect_context
  local project="$_wt_detected_project"
  local feature="$_wt_detected_feature"

  if [[ -z "$project" || -z "$feature" ]]; then
    echo "Error: Must be inside a worktree to run wt merge"
    return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    return 1
  fi

  local feature_dir="$(_wt_strip_branch_prefix "$feature")"
  local wt_path="$WORKTREE_BASE/$project/$feature_dir"

  # Get real branch name from the worktree if it exists
  local branch_name="$feature"
  if [[ -d "$wt_path" ]]; then
    local detected_branch="$(_wt_get_branch "$wt_path")"
    [[ -n "$detected_branch" ]] && branch_name="$detected_branch"
  fi

  # Check if there's a PR for this branch
  local pr_number
  pr_number=$(gh pr list --repo "$(git -C "$repo_path" remote get-url origin)" --head "$branch_name" --json number --jq '.[0].number' 2>/dev/null)

  if [[ -z "$pr_number" ]]; then
    echo "Error: No open PR found for branch '$branch_name'"
    return 1
  fi

  echo "Merging PR #$pr_number for $project/$branch_name ($merge_strategy)..."

  # Move out of worktree if we're in it
  if [[ "$PWD" == "$wt_path"* ]]; then
    cd "$repo_path"
  fi

  # Remove worktree first so the branch isn't checked out anywhere
  if [[ -d "$wt_path" ]]; then
    echo "Removing worktree..."
    git -C "$repo_path" worktree remove "$wt_path" --force
    if [[ -d "$wt_path" ]]; then
      rm -rf "$wt_path"
    fi
  fi

  # Delete local branch (now safe since worktree is gone)
  git -C "$repo_path" branch -D "$branch_name" 2>/dev/null

  # Merge the PR via gh CLI (deletes remote branch)
  local remote_url
  remote_url=$(git -C "$repo_path" remote get-url origin)
  if ! gh pr merge "$pr_number" --repo "$remote_url" $merge_strategy --delete-branch; then
    echo "Error: Failed to merge PR #$pr_number"
    return 1
  fi

  # Switch to main and pull latest
  echo "Updating local main branch..."
  git -C "$repo_path" checkout "$DEFAULT_BASE_BRANCH" 2>/dev/null
  git -C "$repo_path" pull origin "$DEFAULT_BASE_BRANCH"

  cd "$repo_path"
  echo "Done. PR #$pr_number merged, branch deleted, worktree cleaned up."
}

_wt_ls() {
  local project="$1"

  # Auto-detect from current directory
  if [[ -z "$project" ]]; then
    _wt_detect_context
    project="$_wt_detected_project"
  fi

  if [[ -n "$project" ]]; then
    _wt_ls_project "$project"
  else
    local has_worktrees=false
    for p in "${(k)WT_PROJECTS[@]}"; do
      local wt_dir="$WORKTREE_BASE/$p"
      if [[ -d "$wt_dir" ]] && [[ -n "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
        has_worktrees=true
        _wt_ls_project "$p"
        echo ""
      fi
    done
    if ! $has_worktrees; then
      echo "No active worktrees."
    fi
  fi
}

_wt_ls_project() {
  local project="$1"
  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    return 1
  fi

  local remote_url
  remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null)
  local wt_dir="$WORKTREE_BASE/$project"
  local name pr_info pr_num

  echo "$project:"
  for d in "$wt_dir"/*(N/); do
    name="${d:t}"
    pr_info=""

    # Get real branch name from the worktree for PR lookup
    local branch_name="$(_wt_get_branch "$d")"
    [[ -z "$branch_name" ]] && branch_name="$name"

    if [[ -n "$remote_url" ]]; then
      pr_num=$(gh pr list --repo "$remote_url" --head "$branch_name" --json number --jq '.[0].number' 2>/dev/null)

      if [[ -n "$pr_num" && "$pr_num" != "null" ]]; then
        pr_info="  PR #$pr_num"
      else
        pr_info="  No PR"
      fi
    fi

    echo "  $name  ($d)"
    if [[ -n "$pr_info" ]]; then
      echo "   $pr_info"
    fi
  done
}
