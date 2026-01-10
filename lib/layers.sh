#!/usr/bin/env bash
# lib/layers.sh
# Resolve layer specifications to absolute paths

set -euo pipefail

# Source utilities for safe variable expansion
source "${BASH_SOURCE%/*}/utils.sh"

# ============================================================================
# Tool Context - Centralized State Management
# ============================================================================
# Instead of multiple separate globals, we use a single context array.
# This provides:
#   - Clear ownership of state
#   - Explicit initialization before each tool
#   - Easy cleanup between tools
#   - Better testability (just call init_tool_ctx to reset)
#
# Context keys:
#   target         - Target path for the tool config
#   install_hook   - Install hook specification
#   merge_hook     - Merge hook specification
#   layer:<name>   - Layer specification for <name>
#   env:<name>     - Environment variable <name>
#   _env_keys      - Space-separated list of env var names (for iteration)
#   _layer_keys    - Space-separated list of layer names (for iteration)
# ============================================================================

declare -gA TOOL_CTX

# Initialize/reset the tool context
# Usage: init_tool_ctx
# Call this before processing each tool to ensure clean state
init_tool_ctx() {
    # Clear the associative array
    TOOL_CTX=()

    # Initialize with empty defaults
    TOOL_CTX[target]=""
    TOOL_CTX[install_hook]=""
    TOOL_CTX[merge_hook]=""
    TOOL_CTX[_env_keys]=""
    TOOL_CTX[_layer_keys]=""
}

# Get a value from the tool context
# Usage: ctx_get "target"
ctx_get() {
    echo "${TOOL_CTX[$1]:-}"
}

# Get a layer specification from context
# Usage: ctx_get_layer "base"
ctx_get_layer() {
    echo "${TOOL_CTX[layer:$1]:-}"
}

# Get an env var from context
# Usage: ctx_get_env "MY_VAR"
ctx_get_env() {
    echo "${TOOL_CTX[env:$1]:-}"
}

# Check if context has any env vars
# Usage: ctx_has_env_vars && echo "yes"
ctx_has_env_vars() {
    [[ -n "${TOOL_CTX[_env_keys]:-}" ]]
}

# Iterate over env vars in context
# Usage: for key in $(ctx_env_keys); do ...; done
ctx_env_keys() {
    echo "${TOOL_CTX[_env_keys]:-}"
}

# ============================================================================
# Legacy Compatibility Layer
# ============================================================================
# These variables are kept for backward compatibility with existing code.
# New code should use TOOL_CTX directly via ctx_get/ctx_get_layer/etc.
# TODO: Remove these once all callers are updated

TOOL_TARGET=""
TOOL_INSTALL_HOOK=""
TOOL_MERGE_HOOK=""
declare -gA TOOL_LAYERS
declare -gA TOOL_ENV

# Sync context to legacy globals (for backward compatibility)
_sync_ctx_to_legacy() {
    TOOL_TARGET="${TOOL_CTX[target]:-}"
    TOOL_INSTALL_HOOK="${TOOL_CTX[install_hook]:-}"
    TOOL_MERGE_HOOK="${TOOL_CTX[merge_hook]:-}"

    # Clear and repopulate TOOL_LAYERS
    TOOL_LAYERS=()
    for key in ${TOOL_CTX[_layer_keys]:-}; do
        TOOL_LAYERS["$key"]="${TOOL_CTX[layer:$key]:-}"
    done

    # Clear and repopulate TOOL_ENV
    TOOL_ENV=()
    for key in ${TOOL_CTX[_env_keys]:-}; do
        TOOL_ENV["$key"]="${TOOL_CTX[env:$key]:-}"
    done
}

# ============================================================================
# Tool Configuration Parsing
# ============================================================================

# Parse a tool.conf file and populate the tool context
# Usage: parse_tool_conf "/path/to/tool.conf"
# Returns: Populates TOOL_CTX (and legacy globals for compatibility)
parse_tool_conf() {
    local tool_conf="$1"

    if [[ ! -f "$tool_conf" ]]; then
        log_error "tool.conf not found: $tool_conf"
        return 1
    fi

    # Initialize fresh context
    init_tool_ctx

    local env_keys=""
    local layer_keys=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Parse key="value" or key=value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"

            # Expand environment variables (safely, no shell injection)
            value=$(safe_expand_vars "$value")

            case "$key" in
                target)
                    TOOL_CTX[target]="$value"
                    ;;
                install_hook)
                    TOOL_CTX[install_hook]="$value"
                    ;;
                merge_hook)
                    TOOL_CTX[merge_hook]="$value"
                    ;;
                layers_*)
                    local layer_name="${key#layers_}"
                    TOOL_CTX["layer:$layer_name"]="$value"
                    layer_keys="$layer_keys $layer_name"
                    ;;
                env_*)
                    local env_name="${key#env_}"
                    TOOL_CTX["env:$env_name"]="$value"
                    env_keys="$env_keys $env_name"
                    ;;
            esac
        fi
    done < "$tool_conf"

    # Store the keys for iteration
    TOOL_CTX[_env_keys]="${env_keys# }"    # trim leading space
    TOOL_CTX[_layer_keys]="${layer_keys# }"

    # Sync to legacy globals for backward compatibility
    _sync_ctx_to_legacy
}

# Resolve a single layer specification to an absolute path
# Usage: resolve_layer_path "local:base" "/path/to/dotfiles" "nvim"
# Returns: Absolute path to the layer directory
resolve_layer_path() {
    local layer_spec="$1"
    local dotfiles_dir="$2"
    local tool="$3"

    local repo_name="${layer_spec%%:*}"
    local layer_path="${layer_spec#*:}"

    if [[ "$repo_name" == "local" ]]; then
        # Local layer - relative to dotfiles root
        echo "${dotfiles_dir}/${layer_path}"
    else
        # External repo layer
        local repo_path
        repo_path=$(get_repo_path "$repo_name")

        if [[ -z "$repo_path" ]]; then
            log_error "Unknown repository: $repo_name"
            return 1
        fi

        echo "${repo_path}/${layer_path}"
    fi
}

# Resolve all layers for a tool given a list of layer names
# Usage: resolve_layers "nvim" "base:work" "/path/to/dotfiles"
# Returns: Colon-separated absolute paths
resolve_layers() {
    local tool="$1"
    local layer_names="$2"
    local dotfiles_dir="$3"

    local tool_conf="${dotfiles_dir}/tools/${tool}/tool.conf"

    if [[ ! -f "$tool_conf" ]]; then
        log_error "No tool.conf found for: $tool"
        return 1
    fi

    # Parse tool.conf - populates TOOL_CTX
    parse_tool_conf "$tool_conf"

    local resolved_paths=()
    IFS=':' read -ra names <<< "$layer_names"

    for name in "${names[@]}"; do
        # Use context accessor instead of legacy global
        local layer_spec
        layer_spec=$(ctx_get_layer "$name")

        if [[ -z "$layer_spec" ]]; then
            log_error "Layer not defined in tool.conf: $name"
            return 1
        fi

        local resolved_path
        resolved_path=$(resolve_layer_path "$layer_spec" "$dotfiles_dir" "$tool")

        if [[ ! -d "$resolved_path" ]]; then
            log_warn "Layer directory does not exist: $resolved_path"
        fi

        resolved_paths+=("$resolved_path")
    done

    # Join with colons
    local IFS=':'
    echo "${resolved_paths[*]}"
}

# Get layers for a tool from machine profile
# Usage: get_tool_layers "nvim" (requires machine profile to be sourced)
get_tool_layers() {
    local tool="$1"
    local var_name="${tool}_layers[@]"

    # Check if the array exists
    if declare -p "${tool}_layers" &>/dev/null 2>&1; then
        local layers
        eval "layers=(\"\${${tool}_layers[@]}\")"
        local IFS=':'
        echo "${layers[*]}"
    else
        # Default to base layer if not specified
        echo "base"
    fi
}

# Validate that all required layers exist
# Usage: validate_layers "nvim" "base:work" "/path/to/dotfiles"
validate_layers() {
    local tool="$1"
    local layer_names="$2"
    local dotfiles_dir="$3"

    local resolved_paths
    resolved_paths=$(resolve_layers "$tool" "$layer_names" "$dotfiles_dir")

    IFS=':' read -ra paths <<< "$resolved_paths"
    local missing=()

    for path in "${paths[@]}"; do
        if [[ ! -d "$path" ]]; then
            missing+=("$path")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing layer directories:"
        for path in "${missing[@]}"; do
            log_detail "$path"
        done
        return 1
    fi

    return 0
}
