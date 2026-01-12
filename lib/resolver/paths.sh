#!/usr/bin/env bash
# MODULE: resolver/paths
# PURPOSE: Path expansion and resolution utilities
#
# PUBLIC API:
#   path_expand_tilde(path)              - Expand ~ to $HOME
#   path_expand_env_vars(path)           - Expand environment variables
#   path_expand(path)                    - Full expansion (tilde + env vars)
#   path_resolve_relative(path, base)    - Resolve relative path against base
#   path_is_absolute(path)               - Check if path is absolute
#   path_normalize(path)                 - Remove redundant slashes, resolve . and ..
#   path_join(base, path)                - Join two paths safely
#
# DEPENDENCIES: core/errors.sh
#
# NOTES:
#   - All functions are pure (no filesystem I/O)
#   - Invalid input returns E_INVALID_INPUT
#   - Empty paths are treated as invalid

[[ -n "${_RESOLVER_PATHS_LOADED:-}" ]] && return 0
_RESOLVER_PATHS_LOADED=1

# Source dependencies
_RESOLVER_PATHS_DIR="${BASH_SOURCE[0]%/*}"
source "$_RESOLVER_PATHS_DIR/../core/errors.sh"

# Expand tilde (~) to $HOME
# Usage: result=$(path_expand_tilde "~/config")
# Returns: Expanded path on stdout, E_OK or E_INVALID_INPUT
path_expand_tilde() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return $E_INVALID_INPUT
    fi

    # Handle ~ at the start
    if [[ "$path" == "~" ]]; then
        printf '%s' "${HOME:-}"
    elif [[ "$path" == "~/"* ]]; then
        printf '%s' "${HOME:-}${path:1}"
    else
        printf '%s' "$path"
    fi

    return $E_OK
}

# Expand environment variables in a path
# Supports both ${VAR} and $VAR formats
# Usage: result=$(path_expand_env_vars '${HOME}/.config')
# Returns: Expanded path on stdout
path_expand_env_vars() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return $E_INVALID_INPUT
    fi

    local result="$path"

    # Expand ${VAR} format - match full variable names
    while [[ "$result" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        # Replace all occurrences of this specific variable
        result="${result//\$\{${var_name}\}/${var_value}}"
    done

    # Expand $VAR format (not followed by { and followed by / or end)
    # Handle $VAR at end of string
    while [[ "$result" =~ \$([a-zA-Z_][a-zA-Z0-9_]*)(/|$) ]]; do
        local var_name="${BASH_REMATCH[1]}"
        local suffix="${BASH_REMATCH[2]}"
        local var_value="${!var_name:-}"
        result="${result//\$${var_name}/${var_value}}"
    done

    printf '%s' "$result"
    return $E_OK
}

# Full path expansion (tilde + environment variables)
# Usage: result=$(path_expand "~/.config/${USER}")
# Returns: Fully expanded path on stdout
path_expand() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return $E_INVALID_INPUT
    fi

    # First expand tilde
    local result
    result=$(path_expand_tilde "$path") || return $?

    # Then expand env vars
    result=$(path_expand_env_vars "$result") || return $?

    printf '%s' "$result"
    return $E_OK
}

# Resolve a relative path against a base directory
# Usage: result=$(path_resolve_relative "configs/git" "/path/to/dotfiles")
# Returns: Absolute path on stdout
path_resolve_relative() {
    local path="$1"
    local base="$2"

    if [[ -z "$path" ]]; then
        return $E_INVALID_INPUT
    fi

    if [[ -z "$base" ]]; then
        return $E_INVALID_INPUT
    fi

    # If path is already absolute, return it
    if [[ "$path" == /* ]]; then
        printf '%s' "$path"
        return $E_OK
    fi

    # Remove trailing slash from base
    base="${base%/}"

    printf '%s/%s' "$base" "$path"
    return $E_OK
}

# Check if a path is absolute
# Usage: path_is_absolute "/home/user" && echo "absolute"
# Returns: E_OK (0) if absolute, 1 if relative
path_is_absolute() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    # Absolute paths start with / or ~ (tilde will expand to absolute)
    [[ "$path" == /* || "$path" == "~"* ]]
}

# Normalize a path by removing redundant slashes and resolving . and ..
# Note: This is string manipulation only, does not verify path exists
# Usage: result=$(path_normalize "/path//to/../file")
# Returns: Normalized path on stdout
path_normalize() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return $E_INVALID_INPUT
    fi

    # Remove multiple slashes
    local result="${path//\/\//\/}"
    while [[ "$result" == *"//"* ]]; do
        result="${result//\/\//\/}"
    done

    # Remove trailing slash (except for root)
    if [[ "$result" != "/" ]]; then
        result="${result%/}"
    fi

    # Handle . and .. components
    local -a parts=()
    local IFS='/'
    local is_absolute=0

    if [[ "$result" == /* ]]; then
        is_absolute=1
        result="${result:1}"  # Remove leading slash for splitting
    fi

    read -ra segments <<< "$result"

    for segment in "${segments[@]}"; do
        case "$segment" in
            .|"")
                # Skip current dir and empty segments
                continue
                ;;
            ..)
                # Go up one directory if possible
                if [[ ${#parts[@]} -gt 0 && "${parts[-1]}" != ".." ]]; then
                    unset 'parts[-1]'
                elif [[ $is_absolute -eq 0 ]]; then
                    parts+=("..")
                fi
                # For absolute paths, just ignore .. at root
                ;;
            *)
                parts+=("$segment")
                ;;
        esac
    done

    # Reconstruct path
    if [[ $is_absolute -eq 1 ]]; then
        if [[ ${#parts[@]} -eq 0 ]]; then
            printf '/'
        else
            printf '/%s' "${parts[0]}"
            local i
            for ((i = 1; i < ${#parts[@]}; i++)); do
                printf '/%s' "${parts[i]}"
            done
        fi
    else
        if [[ ${#parts[@]} -eq 0 ]]; then
            printf '.'
        else
            printf '%s' "${parts[0]}"
            local i
            for ((i = 1; i < ${#parts[@]}; i++)); do
                printf '/%s' "${parts[i]}"
            done
        fi
    fi

    return $E_OK
}

# Join two paths safely
# Usage: result=$(path_join "/base" "relative/path")
# Returns: Joined path on stdout
path_join() {
    local base="$1"
    local path="$2"

    if [[ -z "$base" ]]; then
        printf '%s' "$path"
        return $E_OK
    fi

    if [[ -z "$path" ]]; then
        printf '%s' "$base"
        return $E_OK
    fi

    # If path is absolute, it overrides base
    if [[ "$path" == /* ]]; then
        printf '%s' "$path"
        return $E_OK
    fi

    # Remove trailing slash from base and join
    printf '%s/%s' "${base%/}" "$path"
    return $E_OK
}
