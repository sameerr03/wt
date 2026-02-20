#!/usr/bin/env zsh

# Load config
source "$(dirname "${(%):-%x}")/config.sh"

wt() {
  local cmd="$1"
  shift

  case "$cmd" in
    new)    _wt_new "$@" ;;
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
  echo "Usage: wt <command> [args]"
  echo ""
  echo "Commands:"
  echo "  new   <project> <feature> [--base <branch>]   Create worktree, install deps, launch Claude"
  echo "  cd    <project> <feature>                     Jump into worktree and continue Claude session"
  echo "  rm    <project> <feature> [--delete-branch]   Remove a worktree"
  echo "  merge <project> <feature> [--squash|--rebase] Merge PR, cleanup worktree & branch, pull main"
  echo "  ls    [project]                               List worktrees with PR status"
  echo "  help                                          Show this help message"
  echo ""
  echo "Configuration:"
  echo "  Edit config.sh to add projects, set package managers, and change defaults."
  echo ""
  echo "Examples:"
  echo "  wt cd carousel fix-slider               Jump into worktree and continue Claude session"
  echo "  wt new carousel fix-slider              Create worktree on new branch from main"
  echo "  wt new carousel fix-slider --base dev   Create worktree branching from dev"
  echo "  wt ls                                   List all worktrees with PR status"
  echo "  wt merge carousel fix-slider            Squash-merge PR, delete branch, remove worktree"
  echo "  wt merge carousel fix-slider --rebase   Rebase-merge instead of squash"
  echo "  wt rm carousel fix-slider               Remove worktree only"
  echo "  wt rm carousel fix-slider --delete-branch  Remove worktree and delete branch"
}

_wt_get_install_cmd() {
  local project="$1"
  if [[ -n "${WT_PKG_MANAGER[$project]}" ]]; then
    echo "${WT_PKG_MANAGER[$project]} install"
  else
    echo "$DEFAULT_INSTALL_CMD"
  fi
}

_wt_cd() {
  local project="$1" feature="$2"

  if [[ -z "$project" || -z "$feature" ]]; then
    echo "Usage: wt cd <project> <feature>"
    return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    echo "Available projects: ${(k)WT_PROJECTS}"
    return 1
  fi

  local wt_path="$WORKTREE_BASE/$project/$feature"

  if [[ ! -d "$wt_path" ]]; then
    echo "Error: No worktree found at $wt_path"
    return 1
  fi

  cd "$wt_path"
  claude --continue
}

_wt_new() {
  local project="" feature="" base_branch="$DEFAULT_BASE_BRANCH"

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
        elif [[ -z "$feature" ]]; then
          feature="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$project" || -z "$feature" ]]; then
    echo "Usage: wt new <project> <feature> [--base <branch>]"
    return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    echo "Available projects: ${(k)WT_PROJECTS}"
    return 1
  fi

  local wt_path="$WORKTREE_BASE/$project/$feature"

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

_wt_rm() {
  local project="" feature="" delete_branch=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --delete-branch)
        delete_branch=true
        shift
        ;;
      *)
        if [[ -z "$project" ]]; then
          project="$1"
        elif [[ -z "$feature" ]]; then
          feature="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$project" || -z "$feature" ]]; then
    echo "Usage: wt rm <project> <feature> [--delete-branch]"
    return 1
  fi

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

  if $delete_branch; then
    echo "Deleting branch '$feature'..."
    git -C "$repo_path" branch -D "$feature" 2>/dev/null
  fi

  echo "Done."
}

_wt_merge() {
  local project="" feature="" merge_strategy="--squash"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --squash)
        merge_strategy="--squash"
        shift
        ;;
      --rebase)
        merge_strategy="--rebase"
        shift
        ;;
      *)
        if [[ -z "$project" ]]; then
          project="$1"
        elif [[ -z "$feature" ]]; then
          feature="$1"
        fi
        shift
        ;;
    esac
  done

  if [[ -z "$project" || -z "$feature" ]]; then
    echo "Usage: wt merge <project> <feature> [--squash|--rebase]"
    return 1
  fi

  local repo_path="${WT_PROJECTS[$project]}"
  if [[ -z "$repo_path" ]]; then
    echo "Error: Unknown project '$project'"
    return 1
  fi

  local wt_path="$WORKTREE_BASE/$project/$feature"

  # Check if there's a PR for this branch
  local pr_number
  pr_number=$(gh pr list --repo "$(git -C "$repo_path" remote get-url origin)" --head "$feature" --json number --jq '.[0].number' 2>/dev/null)

  if [[ -z "$pr_number" ]]; then
    echo "Error: No open PR found for branch '$feature'"
    return 1
  fi

  echo "Merging PR #$pr_number for $project/$feature ($merge_strategy)..."

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
  git -C "$repo_path" branch -D "$feature" 2>/dev/null

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

  echo "$project:"
  for d in "$wt_dir"/*(N/); do
    local name="${d:t}"
    local pr_info=""

    if [[ -n "$remote_url" ]]; then
      local pr_json
      pr_json=$(gh pr list --repo "$remote_url" --head "$name" --json number,state,reviewDecision,statusCheckRollup --jq '.[0]' 2>/dev/null)

      if [[ -n "$pr_json" && "$pr_json" != "null" ]]; then
        local pr_num=$(echo "$pr_json" | jq -r '.number')
        local review=$(echo "$pr_json" | jq -r '.reviewDecision // "PENDING"')
        local checks=$(echo "$pr_json" | jq -r '
          if (.statusCheckRollup | length) == 0 then "NO CHECKS"
          elif [.statusCheckRollup[] | select(.conclusion != "SUCCESS" and .conclusion != "")] | length == 0 then "✓ CHECKS PASS"
          else "✗ CHECKS FAILING"
          end
        ')

        case "$review" in
          APPROVED)           review="✓ approved" ;;
          CHANGES_REQUESTED)  review="✗ changes requested" ;;
          REVIEW_REQUIRED)    review="⏳ review needed" ;;
          *)                  review="⏳ no reviews" ;;
        esac

        pr_info="  PR #$pr_num — $review, $checks"
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
