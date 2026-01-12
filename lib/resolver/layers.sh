#!/usr/bin/env bash
# MODULE: resolver/layers
# PURPOSE: Layer specification resolution
#
# PUBLIC API:
#   layer_resolver_init(dotfiles_dir)     - Initialize resolver with dotfiles path
#   layer_resolve_spec(spec)              - Resolve "source:path" to absolute path
#   layer_resolve_tool_config(config_ref) - Resolve all layers in a ToolConfig
#   layer_parse_spec(spec, source_out, path_out) - Parse spec into components
#   layer_get_dotfiles_dir()              - Get current dotfiles directory
#
# DEPENDENCIES:
#   core/errors.sh
#   core/fs.sh
#   contracts/tool_config.sh
#   resolver/paths.sh
#   resolver/repos.sh
#
# LAYER SPEC FORMAT:
#   "local:relative/path"      - Path relative to DOTFILES_DIR
#   "REPO_NAME:relative/path"  - Path relative to external repo
#
# NOTES:
#   - Resolved paths are absolute
#   - Missing directories are not an error (caller should validate)
#   - Unknown repo names return E_NOT_FOUND

[[ -n "${_RESOLVER_LAYERS_LOADED:-}" ]] && return 0
_RESOLVER_LAYERS_LOADED=1

# Source dependencies
_RESOLVER_LAYERS_DIR="${BASH_SOURCE[0]%/*}"
source "$_RESOLVER_LAYERS_DIR/../core/errors.sh"
source "$_RESOLVER_LAYERS_DIR/../core/fs.sh"
source "$_RESOLVER_LAYERS_DIR/../contracts/tool_config.sh"
source "$_RESOLVER_LAYERS_DIR/paths.sh"
source "$_RESOLVER_LAYERS_DIR/repos.sh"

# --- State ---
_layer_resolver_dotfiles_dir=""

# --- Initialization ---

# Initialize the layer resolver
# Usage: layer_resolver_init "/path/to/dotfiles"
# Returns: E_OK on success
layer_resolver_init() {
    local dotfiles_dir="$1"

    if [[ -z "$dotfiles_dir" ]]; then
        return $E_INVALID_INPUT
    fi

    # Expand the path (handles ~ and env vars)
    _layer_resolver_dotfiles_dir=$(path_expand "$dotfiles_dir") || return $?

    # Initialize repos from repos.conf
    repos_init "$_layer_resolver_dotfiles_dir"

    return $E_OK
}

# Get current dotfiles directory
# Usage: dir=$(layer_get_dotfiles_dir)
layer_get_dotfiles_dir() {
    printf '%s' "$_layer_resolver_dotfiles_dir"
}

# --- Public API ---

# Parse a layer specification into source and path components
# Usage: layer_parse_spec "local:configs/git" source_var path_var
# Returns: E_OK and sets variables, or E_INVALID_INPUT
layer_parse_spec() {
    local spec="$1"
    local -n __lps_source=$2
    local -n __lps_path=$3

    if [[ -z "$spec" ]]; then
        return $E_INVALID_INPUT
    fi

    # Check for colon separator
    if [[ "$spec" != *":"* ]]; then
        return $E_INVALID_INPUT
    fi

    # Split on first colon
    __lps_source="${spec%%:*}"
    __lps_path="${spec#*:}"

    # Validate source is not empty
    if [[ -z "$__lps_source" ]]; then
        return $E_INVALID_INPUT
    fi

    # Validate path is not empty
    if [[ -z "$__lps_path" ]]; then
        return $E_INVALID_INPUT
    fi

    return $E_OK
}

# Resolve a layer specification to an absolute path
# Usage: path=$(layer_resolve_spec "local:configs/git")
# Returns: Absolute path on stdout, or E_NOT_FOUND/E_INVALID_INPUT
layer_resolve_spec() {
    local spec="$1"

    if [[ -z "$spec" ]]; then
        return $E_INVALID_INPUT
    fi

    local source path
    if ! layer_parse_spec "$spec" source path; then
        return $E_INVALID_INPUT
    fi

    local base_dir

    if [[ "$source" == "local" ]]; then
        # Local source - relative to dotfiles directory
        base_dir="$_layer_resolver_dotfiles_dir"
    else
        # External repository source
        local repo_path
        if ! repo_path=$(repos_get_path "$source"); then
            return $E_NOT_FOUND
        fi
        base_dir="$repo_path"
    fi

    # Resolve the relative path against the base directory
    local resolved
    resolved=$(path_resolve_relative "$path" "$base_dir") || return $?

    # Normalize the path
    resolved=$(path_normalize "$resolved") || return $?

    printf '%s' "$resolved"
    return $E_OK
}

# Resolve all layers in a ToolConfig
# Usage: layer_resolve_tool_config config
# Modifies: Sets resolved_path for each layer in config
# Returns: E_OK on success, or first error encountered
layer_resolve_tool_config() {
    local -n __lrtc_config=$1

    local layer_count
    layer_count=$(tool_config_get_layer_count __lrtc_config)

    local i
    for ((i = 0; i < layer_count; i++)); do
        local source path
        source=$(tool_config_get_layer_source __lrtc_config "$i")
        path=$(tool_config_get_layer_path __lrtc_config "$i")

        # Build spec from source and path
        local spec="${source}:${path}"

        # Resolve the spec
        local resolved
        if ! resolved=$(layer_resolve_spec "$spec"); then
            local name
            name=$(tool_config_get_layer_name __lrtc_config "$i")
            echo "Failed to resolve layer '$name': $spec" >&2
            return $E_NOT_FOUND
        fi

        # Store the resolved path
        tool_config_set_layer_resolved __lrtc_config "$i" "$resolved"
    done

    return $E_OK
}

# Validate that all resolved layer paths exist
# Usage: layer_validate_resolved config
# Returns: E_OK if all exist, E_NOT_FOUND with list of missing
layer_validate_resolved() {
    local -n __lvr_config=$1

    local layer_count
    layer_count=$(tool_config_get_layer_count __lvr_config)

    local missing=()
    local i
    for ((i = 0; i < layer_count; i++)); do
        local resolved
        resolved=$(tool_config_get_layer_resolved __lvr_config "$i")

        if [[ -z "$resolved" ]]; then
            local name
            name=$(tool_config_get_layer_name __lvr_config "$i")
            missing+=("$name (not resolved)")
            continue
        fi

        if ! fs_is_dir "$resolved"; then
            local name
            name=$(tool_config_get_layer_name __lvr_config "$i")
            missing+=("$name ($resolved)")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Missing layer directories:" >&2
        printf '  - %s\n' "${missing[@]}" >&2
        return $E_NOT_FOUND
    fi

    return $E_OK
}

# Get resolved paths as colon-separated string
# Usage: paths=$(layer_get_resolved_paths config)
# Returns: Colon-separated absolute paths on stdout
layer_get_resolved_paths() {
    local -n __lgrp_config=$1

    local layer_count
    layer_count=$(tool_config_get_layer_count __lgrp_config)

    local paths=""
    local i
    for ((i = 0; i < layer_count; i++)); do
        local resolved
        resolved=$(tool_config_get_layer_resolved __lgrp_config "$i")

        if [[ -z "$paths" ]]; then
            paths="$resolved"
        else
            paths="${paths}:${resolved}"
        fi
    done

    printf '%s' "$paths"
    return $E_OK
}
