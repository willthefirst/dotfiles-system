#!/usr/bin/env bash
# lib/utils.sh
# Safe utility functions for the dotfiles framework

set -euo pipefail

# ============================================================================
# Source Guard
# ============================================================================

[[ -n "${_DOTFILES_UTILS_LOADED:-}" ]] && return 0
_DOTFILES_UTILS_LOADED=1

# Source logging utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../helpers/log.sh"

# ============================================================================
# Safe Variable Expansion
# ============================================================================

# Safe environment variable expansion
# Expands ${VAR}, ${VAR:-default}, and $VAR patterns, NOT shell commands
# This replaces unsafe `eval echo "$value"` patterns
#
# Usage: safe_expand_vars "path/to/${HOME}/file"
# Returns: Expanded string with environment variables resolved
safe_expand_vars() {
    local input="$1"
    local result="$input"
    local max_iterations=50  # Prevent infinite loops
    local iteration=0

    # Expand ${VAR:-default} patterns first (more specific)
    while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\} ]] && (( iteration++ < max_iterations )); do
        local var_name="${BASH_REMATCH[1]}"
        local default_value="${BASH_REMATCH[2]}"
        local var_value="${!var_name:-$default_value}"
        # Escape special chars in the pattern for replacement
        local pattern="\${${var_name}:-${default_value}}"
        result="${result/"$pattern"/$var_value}"
    done

    # Expand ${VAR} patterns
    iteration=0
    while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]] && (( iteration++ < max_iterations )); do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        result="${result/\$\{$var_name\}/$var_value}"
    done

    # Expand $VAR patterns (must not be followed by valid identifier chars)
    iteration=0
    while [[ "$result" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]] && (( iteration++ < max_iterations )); do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        # Use a more careful replacement to avoid partial matches
        result="${result/\$$var_name/$var_value}"
    done

    echo "$result"
}

# ============================================================================
# Safe File Operations
# ============================================================================

# Safe removal with automatic backup
# Moves target to backup directory instead of deleting
#
# Usage: safe_remove "/path/to/target" [backup_dir]
# Returns: 0 on success, 1 on failure
safe_remove() {
    local target="$1"
    local backup_dir="${2:-${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}}"

    # Nothing to do if target doesn't exist
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        return 0
    fi

    # Create backup directory
    mkdir -p "$backup_dir"

    # Generate unique backup name
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local target_basename
    target_basename=$(basename "$target")
    local backup_name="${target_basename}_${timestamp}"

    # Ensure uniqueness if multiple backups in same second
    local backup_path="$backup_dir/$backup_name"
    local counter=1
    while [[ -e "$backup_path" ]]; do
        backup_path="$backup_dir/${backup_name}_${counter}"
        ((counter++))
    done

    # Move to backup instead of delete
    mv "$target" "$backup_path"
    log_detail "Backed up: $target -> $backup_path"
}

# Safe recursive removal with backup (alias for consistency)
# Usage: safe_remove_rf "/path/to/directory"
safe_remove_rf() {
    safe_remove "$1" "${2:-}"
}

# ============================================================================
# File Discovery
# ============================================================================

# Find a config file within a layer directory
# Searches for common config file patterns in priority order
#
# Usage: find_config_file "/path/to/layer" "target_name" [extension]
# Returns: Path to config file (stdout), or returns 1 if not found
#
# Search priority:
#   1. $layer_path/$target_name
#   2. $layer_path/config.$extension (if extension provided)
#   3. $layer_path/config
#   4. $layer_path/init
#   5. First file in directory (with extension filter if provided)
find_config_file() {
    local layer_path="$1"
    local target_name="$2"
    local extension="${3:-}"

    # Not a directory? Can't search
    if [[ ! -d "$layer_path" ]]; then
        # If layer_path is a file itself, return it
        if [[ -f "$layer_path" ]]; then
            echo "$layer_path"
            return 0
        fi
        return 1
    fi

    # Build candidate list
    local candidates=(
        "$layer_path/$target_name"
    )

    # Add extension-specific candidates if extension provided
    if [[ -n "$extension" ]]; then
        candidates+=(
            "$layer_path/config.$extension"
            "$layer_path/$target_name.$extension"
        )
    fi

    # Add generic candidates
    candidates+=(
        "$layer_path/config"
        "$layer_path/init"
    )

    # Try each candidate in order
    for candidate in "${candidates[@]}"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    # Fallback: find first file in directory
    local find_args=(-maxdepth 1 -type f)
    if [[ -n "$extension" ]]; then
        find_args+=(-name "*.$extension")
    fi

    local first_file
    first_file=$(find "$layer_path" "${find_args[@]}" 2>/dev/null | head -1)
    if [[ -n "$first_file" ]]; then
        echo "$first_file"
        return 0
    fi

    return 1
}

# ============================================================================
# Layer Helpers
# ============================================================================

# Parse LAYERS and LAYER_PATHS environment variables into arrays
# Sets global arrays: LAYER_NAMES_ARRAY, LAYER_PATHS_ARRAY
#
# Usage: parse_layers
# Expects: LAYERS and LAYER_PATHS environment variables to be set
parse_layers() {
    IFS=':' read -ra LAYER_NAMES_ARRAY <<< "${LAYERS:-}"
    IFS=':' read -ra LAYER_PATHS_ARRAY <<< "${LAYER_PATHS:-}"
}

# Iterate over layers and execute a callback for each
# The callback receives: index, layer_name, layer_path
#
# Usage: for_each_layer my_callback_function
# Example callback:
#   process_layer() {
#       local index="$1" name="$2" path="$3"
#       echo "Layer $index: $name at $path"
#   }
for_each_layer() {
    local callback="$1"
    parse_layers

    for i in "${!LAYER_PATHS_ARRAY[@]}"; do
        "$callback" "$i" "${LAYER_NAMES_ARRAY[$i]:-}" "${LAYER_PATHS_ARRAY[$i]}"
    done
}

# Get the last (highest priority) layer path
# Usage: last_layer_path
# Returns: Path to the last layer
last_layer_path() {
    parse_layers
    echo "${LAYER_PATHS_ARRAY[-1]:-}"
}

# ============================================================================
# Source Guard Helper
# ============================================================================

# Helper for implementing source guards in other files
# Usage: source_guard "MODULE_NAME" && return 0
# Returns: 0 if already loaded (caller should return), 1 if first load
source_guard() {
    local guard_var="_DOTFILES_${1}_LOADED"
    if [[ -n "${!guard_var:-}" ]]; then
        return 0
    fi
    declare -g "$guard_var=1"
    return 1
}
