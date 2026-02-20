#!/usr/bin/env zsh

# Load config
source "$(dirname "${(%):-%x}")/config.sh"

wt() {
  local cmd="$1"
  shift

  case "$cmd" in
    new)  _wt_new "$@" ;;
    rm)   _wt_rm "$@" ;;
    ls)   _wt_ls "$@" ;;
    *)
      echo "Usage: wt <command> [args]"
      echo ""
      echo "Commands:"
      echo "  new <project> <feature> [--base <branch>]   Create a new worktree"
      echo "  rm  <project> <feature> [--delete-branch]   Remove a worktree"
      echo "  ls  [project]                               List active worktrees"
      return 1
      ;;
  esac
}

_wt_get_install_cmd() {
  local project="$1"
  if [[ -n "${WT_PKG_MANAGER[$project]}" ]]; then
    echo "${WT_PKG_MANAGER[$project]} install"
  else
    echo "$DEFAULT_INSTALL_CMD"
  fi
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

_wt_ls() {
  local project="$1"

  if [[ -n "$project" ]]; then
    local repo_path="${WT_PROJECTS[$project]}"
    if [[ -z "$repo_path" ]]; then
      echo "Error: Unknown project '$project'"
      return 1
    fi
    echo "Worktrees for $project:"
    git -C "$repo_path" worktree list
  else
    for p in "${(k)WT_PROJECTS[@]}"; do
      local repo="${WT_PROJECTS[$p]}"
      local wt_dir="$WORKTREE_BASE/$p"
      # Only show projects that have worktrees
      if [[ -d "$wt_dir" ]] && [[ -n "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
        echo "$p:"
        for d in "$wt_dir"/*(N/); do
          local name="${d:t}"
          echo "  $name  ($d)"
        done
        echo ""
      fi
    done
    if [[ -z "$(ls -A "$WORKTREE_BASE" 2>/dev/null)" ]]; then
      echo "No active worktrees."
    fi
  fi
}
