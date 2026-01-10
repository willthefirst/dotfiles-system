#!/usr/bin/env bash
# lib/repos.sh
# Clone and update external repositories

set -euo pipefail

# Source utilities for safe variable expansion
source "${BASH_SOURCE%/*}/utils.sh"

# Source repos.conf and load repository definitions
# Returns: Sets global associative arrays REPO_URLS and REPO_PATHS
load_repos_conf() {
    local dotfiles_dir="$1"
    local repos_conf="${dotfiles_dir}/repos.conf"

    declare -gA REPO_URLS
    declare -gA REPO_PATHS

    if [[ ! -f "$repos_conf" ]]; then
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Parse NAME="url|path" format
        if [[ "$line" =~ ^([A-Z_][A-Z0-9_]*)=\"([^|]+)\|([^\"]+)\"$ ]]; then
            local name="${BASH_REMATCH[1]}"
            local url="${BASH_REMATCH[2]}"
            local path="${BASH_REMATCH[3]}"

            # Expand environment variables in path (safely, no shell injection)
            path=$(safe_expand_vars "$path")

            REPO_URLS["$name"]="$url"
            REPO_PATHS["$name"]="$path"
        fi
    done < "$repos_conf"
}

# Get the local path for a repo by name
# Usage: get_repo_path "WORK_DOTFILES"
get_repo_path() {
    local name="$1"
    echo "${REPO_PATHS[$name]:-}"
}

# Get the git URL for a repo by name
# Usage: get_repo_url "WORK_DOTFILES"
get_repo_url() {
    local name="$1"
    echo "${REPO_URLS[$name]:-}"
}

# Check if a repo exists locally
# Usage: repo_exists "WORK_DOTFILES"
repo_exists() {
    local name="$1"
    local path="${REPO_PATHS[$name]:-}"

    [[ -n "$path" && -d "$path/.git" ]]
}

# Clone a repository if it doesn't exist
# Usage: ensure_repo "WORK_DOTFILES"
ensure_repo() {
    local name="$1"
    local url="${REPO_URLS[$name]:-}"
    local path="${REPO_PATHS[$name]:-}"

    if [[ -z "$url" || -z "$path" ]]; then
        log_error "Unknown repository: $name"
        return 1
    fi

    if [[ -d "$path/.git" ]]; then
        log_ok "Repository exists: $name"
        return 0
    fi

    log_step "Cloning repository: $name"
    log_detail "URL: $url"
    log_detail "Path: $path"

    mkdir -p "$(dirname "$path")"
    git clone "$url" "$path"
}

# Update a repository (pull latest)
# Usage: update_repo "WORK_DOTFILES"
update_repo() {
    local name="$1"
    local path="${REPO_PATHS[$name]:-}"

    if [[ -z "$path" || ! -d "$path/.git" ]]; then
        log_error "Repository not found: $name"
        return 1
    fi

    log_step "Updating repository: $name"
    (cd "$path" && git pull --ff-only)
}

# Ensure all repositories needed for a set of layers exist
# Usage: ensure_repos_for_layers "base:work" (colon-separated layer names)
ensure_repos_for_layers() {
    local layers="$1"
    local dotfiles_dir="$2"
    local tool="$3"
    local tool_conf="${dotfiles_dir}/tools/${tool}/tool.conf"

    if [[ ! -f "$tool_conf" ]]; then
        return 0
    fi

    IFS=':' read -ra layer_array <<< "$layers"

    for layer in "${layer_array[@]}"; do
        # Read layer definition from tool.conf
        local layer_def
        layer_def=$(grep "^layers_${layer}=" "$tool_conf" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"')

        if [[ -z "$layer_def" ]]; then
            continue
        fi

        # Parse "repo:path" format
        local repo_name="${layer_def%%:*}"

        # Skip local layers
        if [[ "$repo_name" == "local" ]]; then
            continue
        fi

        # Ensure the external repo exists
        if [[ -n "${REPO_URLS[$repo_name]:-}" ]]; then
            ensure_repo "$repo_name"
        fi
    done
}

# List all configured repositories
list_repos() {
    echo "Configured repositories:"
    for name in "${!REPO_URLS[@]}"; do
        local url="${REPO_URLS[$name]}"
        local path="${REPO_PATHS[$name]}"
        local status="not cloned"
        [[ -d "$path/.git" ]] && status="cloned"
        echo "  $name: $path ($status)"
    done
}
