#!/usr/bin/env bash
# MODULE: resolver/repos
# PURPOSE: External repository management
#
# PUBLIC API:
#   repos_init(dotfiles_dir)              - Initialize repos from repos.json
#   repos_get_path(repo_name)             - Get local path for repository
#   repos_get_url(repo_name)              - Get git URL for repository
#   repos_exists(repo_name)               - Check if repo is cloned locally
#   repos_ensure(repo_name)               - Clone repo if not present
#   repos_update(repo_name)               - Pull latest changes
#   repos_list()                          - List all configured repos
#   repos_is_configured(repo_name)        - Check if repo is in config
#
# MOCK API (for testing):
#   repos_mock_set(name, url, path)       - Add mock repo config
#   repos_mock_set_exists(name, exists)   - Set whether repo exists on disk
#   repos_mock_reset()                    - Clear mock state
#
# DEPENDENCIES: core/fs.sh, core/errors.sh, resolver/paths.sh, jq
#
# CONFIGURATION:
#   repos.json format:
#   {
#     "repositories": [
#       { "name": "REPO_NAME", "url": "git_url", "path": "~/local_path" }
#     ]
#   }
#
# NOTES:
#   - Git operations use real git command (not mockable in unit tests)
#   - Use integration tests for full git workflow verification
#   - repos_exists checks for .git directory presence
#   - ~ in JSON paths expands to $HOME

[[ -n "${_RESOLVER_REPOS_LOADED:-}" ]] && return 0
_RESOLVER_REPOS_LOADED=1

# Source dependencies
_RESOLVER_REPOS_DIR="${BASH_SOURCE[0]%/*}"
source "$_RESOLVER_REPOS_DIR/../core/errors.sh"
source "$_RESOLVER_REPOS_DIR/../core/fs.sh"
source "$_RESOLVER_REPOS_DIR/paths.sh"

# --- State ---
declare -gA _repos_urls=()
declare -gA _repos_paths=()
declare -gA _repos_mock_exists=()  # For testing: override exists check
_repos_dotfiles_dir=""
_repos_use_mock_exists=0

# --- Initialization ---

# Initialize repository configuration from repos.json
# Usage: repos_init "/path/to/dotfiles"
# Returns: E_OK on success (repos are optional), E_VALIDATION if JSON is invalid
repos_init() {
    local dotfiles_dir="$1"

    if [[ -z "$dotfiles_dir" ]]; then
        return $E_INVALID_INPUT
    fi

    _repos_dotfiles_dir="$dotfiles_dir"
    _repos_urls=()
    _repos_paths=()

    # Parse repos.json (optional - not all dotfiles repos need external deps)
    _repos_init_json "$dotfiles_dir"
}

# Parse repos.json file
# Usage: _repos_init_json "/path/to/dotfiles"
# Returns: E_OK on success, E_NOT_FOUND if no JSON file
_repos_init_json() {
    local dotfiles_dir="$1"
    local json_path="$dotfiles_dir/repos.json"

    if ! fs_exists "$json_path"; then
        return $E_NOT_FOUND
    fi

    local content
    if ! content=$(fs_read "$json_path"); then
        return $E_NOT_FOUND
    fi

    # Validate JSON syntax
    if ! echo "$content" | jq . &>/dev/null; then
        echo "resolver/repos: invalid JSON in $json_path" >&2
        return $E_VALIDATION
    fi

    # Parse repositories array
    local i=0
    while true; do
        local name url path
        name=$(echo "$content" | jq -r ".repositories[$i].name // empty")
        [[ -z "$name" ]] && break

        url=$(echo "$content" | jq -r ".repositories[$i].url")
        path=$(echo "$content" | jq -r ".repositories[$i].path")

        # Expand ~ to $HOME in path
        path="${path/#\~/$HOME}"

        _repos_urls["$name"]="$url"
        _repos_paths["$name"]="$path"
        ((i++)) || true
    done

    return $E_OK
}

# --- Public API ---

# Get local path for a repository
# Usage: path=$(repos_get_path "STRIPE_DOTFILES")
# Returns: Path on stdout, E_OK or E_NOT_FOUND
repos_get_path() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    local path="${_repos_paths[$name]:-}"

    if [[ -z "$path" ]]; then
        return $E_NOT_FOUND
    fi

    printf '%s' "$path"
    return $E_OK
}

# Get git URL for a repository
# Usage: url=$(repos_get_url "STRIPE_DOTFILES")
# Returns: URL on stdout, E_OK or E_NOT_FOUND
repos_get_url() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    local url="${_repos_urls[$name]:-}"

    if [[ -z "$url" ]]; then
        return $E_NOT_FOUND
    fi

    printf '%s' "$url"
    return $E_OK
}

# Check if a repository is configured
# Usage: repos_is_configured "STRIPE_DOTFILES" && echo "configured"
# Returns: E_OK (0) if configured, 1 if not
repos_is_configured() {
    local name="$1"

    [[ -n "$name" && -n "${_repos_paths[$name]+set}" ]]
}

# Check if a repository exists locally (is cloned)
# Usage: repos_exists "STRIPE_DOTFILES" && echo "exists"
# Returns: E_OK (0) if exists, 1 if not
repos_exists() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return 1
    fi

    # Check mock override first (for testing)
    if [[ $_repos_use_mock_exists -eq 1 && -n "${_repos_mock_exists[$name]+set}" ]]; then
        [[ "${_repos_mock_exists[$name]}" == "1" ]]
        return $?
    fi

    local path="${_repos_paths[$name]:-}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    # Check for .git directory
    fs_is_dir "$path/.git"
}

# Ensure a repository is cloned
# Usage: repos_ensure "STRIPE_DOTFILES"
# Returns: E_OK on success, E_NOT_FOUND if not configured, E_DEPENDENCY if git fails
repos_ensure() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    local url="${_repos_urls[$name]:-}"
    local path="${_repos_paths[$name]:-}"

    if [[ -z "$url" || -z "$path" ]]; then
        return $E_NOT_FOUND
    fi

    # Already exists
    if repos_exists "$name"; then
        return $E_OK
    fi

    # Clone the repository
    local parent_dir
    parent_dir=$(dirname "$path")

    # Ensure parent directory exists
    fs_mkdir "$parent_dir"

    # Run git clone (real git, not mockable)
    if [[ "$(fs_get_backend)" == "mock" ]]; then
        # In mock mode, just mark as existing
        _repos_mock_exists["$name"]="1"
        return $E_OK
    fi

    if ! git clone "$url" "$path" 2>/dev/null; then
        return $E_DEPENDENCY
    fi

    return $E_OK
}

# Update a repository (git pull)
# Usage: repos_update "STRIPE_DOTFILES"
# Returns: E_OK on success, E_NOT_FOUND if not cloned
repos_update() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    local path="${_repos_paths[$name]:-}"

    if [[ -z "$path" ]]; then
        return $E_NOT_FOUND
    fi

    if ! repos_exists "$name"; then
        return $E_NOT_FOUND
    fi

    # In mock mode, just succeed
    if [[ "$(fs_get_backend)" == "mock" ]]; then
        return $E_OK
    fi

    # Run git pull
    if ! (cd "$path" && git pull --ff-only 2>/dev/null); then
        return $E_DEPENDENCY
    fi

    return $E_OK
}

# List all configured repositories
# Usage: names=$(repos_list)
# Returns: Space-separated list of repo names on stdout
repos_list() {
    local names=""

    for name in "${!_repos_urls[@]}"; do
        if [[ -z "$names" ]]; then
            names="$name"
        else
            names="$names $name"
        fi
    done

    printf '%s' "$names"
    return $E_OK
}

# --- Mock API (for testing) ---

# Add a mock repository configuration
# Usage: repos_mock_set "STRIPE_DOTFILES" "git@github.com:..." "/path/to/repo"
repos_mock_set() {
    local name="$1"
    local url="$2"
    local path="$3"

    _repos_urls["$name"]="$url"
    _repos_paths["$name"]="$path"
}

# Set whether a mock repo exists on disk
# Usage: repos_mock_set_exists "STRIPE_DOTFILES" 1
repos_mock_set_exists() {
    local name="$1"
    local exists="$2"

    _repos_use_mock_exists=1
    _repos_mock_exists["$name"]="$exists"
}

# Clear all mock state
repos_mock_reset() {
    _repos_urls=()
    _repos_paths=()
    _repos_mock_exists=()
    _repos_dotfiles_dir=""
    _repos_use_mock_exists=0
}
