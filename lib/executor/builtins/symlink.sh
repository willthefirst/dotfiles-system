#!/usr/bin/env bash
# MODULE: executor/builtins/symlink
# PURPOSE: Symlink merge strategy - symlinks last layer to target
#
# PUBLIC API:
#   builtin_merge_symlink(config_ref, result_ref)
#       Symlinks the last layer to the target path.
#       Supports both file and directory layers.
#
# DEPENDENCIES:
#   core/fs.sh, core/log.sh, core/backup.sh, core/errors.sh
#   contracts/tool_config.sh, contracts/hook_result.sh

[[ -n "${_BUILTIN_SYMLINK_LOADED:-}" ]] && return 0
_BUILTIN_SYMLINK_LOADED=1

# Source dependencies
_BUILTIN_SYMLINK_DIR="${BASH_SOURCE[0]%/*}"
source "$_BUILTIN_SYMLINK_DIR/../../core/fs.sh"
source "$_BUILTIN_SYMLINK_DIR/../../core/log.sh"
source "$_BUILTIN_SYMLINK_DIR/../../core/backup.sh"
source "$_BUILTIN_SYMLINK_DIR/../../core/errors.sh"
source "$_BUILTIN_SYMLINK_DIR/../../contracts/tool_config.sh"
source "$_BUILTIN_SYMLINK_DIR/../../contracts/hook_result.sh"

# Find a config file within a layer directory
# Searches for common config file patterns in priority order
# Usage: _symlink_find_config_file layer_path target_name
_symlink_find_config_file() {
    local layer_path="$1"
    local target_name="$2"

    # If layer_path is a file, return it
    if fs_is_file "$layer_path"; then
        printf '%s' "$layer_path"
        return 0
    fi

    # If layer_path is a directory, search for config file
    if ! fs_is_dir "$layer_path"; then
        return 1
    fi

    # Candidate files in priority order
    local candidates=(
        "$layer_path/$target_name"
        "$layer_path/config"
        "$layer_path/init"
    )

    for candidate in "${candidates[@]}"; do
        if fs_is_file "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    # Fallback: first file in directory (mock-compatible)
    if [[ "$(fs_get_backend)" == "mock" ]]; then
        local files
        files=$(fs_list "$layer_path")
        if [[ -n "$files" ]]; then
            local first
            first=$(echo "$files" | head -1)
            if [[ -n "$first" ]] && fs_is_file "$layer_path/$first"; then
                printf '%s' "$layer_path/$first"
                return 0
            fi
        fi
    else
        local first_file
        first_file=$(find "$layer_path" -maxdepth 1 -type f 2>/dev/null | head -1)
        if [[ -n "$first_file" ]]; then
            printf '%s' "$first_file"
            return 0
        fi
    fi

    return 1
}

# Symlink merge strategy
# Usage: builtin_merge_symlink config result
builtin_merge_symlink() {
    local -n __bms_config=$1
    local -n __bms_result=$2

    local layer_count
    layer_count=$(tool_config_get_layer_count __bms_config)

    if [[ $layer_count -eq 0 ]]; then
        hook_result_new_failure __bms_result $E_INVALID_INPUT "No layers defined"
        return $E_INVALID_INPUT
    fi

    # Get the last layer (highest priority)
    local last_idx=$((layer_count - 1))
    local last_layer
    last_layer=$(tool_config_get_layer_resolved __bms_config "$last_idx")

    if [[ -z "$last_layer" ]]; then
        hook_result_new_failure __bms_result $E_NOT_FOUND "Layer not resolved"
        return $E_NOT_FOUND
    fi

    # Check layer exists
    if ! fs_exists "$last_layer"; then
        hook_result_new_failure __bms_result $E_NOT_FOUND "Layer path not found: $last_layer"
        return $E_NOT_FOUND
    fi

    # Get target path
    local target
    target=$(tool_config_get_target __bms_config)
    # Expand tilde
    if [[ "$target" == "~"* ]]; then
        target="${target/#\~/$HOME}"
    fi

    local target_parent
    target_parent=$(dirname "$target")

    # Ensure parent directory exists
    fs_mkdir "$target_parent"

    # Handle directory vs file layer
    if fs_is_dir "$last_layer"; then
        # Layer is a directory - symlink the directory
        log_detail "Layer is directory: $last_layer"

        # Backup existing target
        if fs_exists "$target"; then
            local backup_path=""
            if ! backup_create "$target" backup_path; then
                hook_result_new_failure __bms_result $E_BACKUP "Backup failed for: $target"
                return $E_BACKUP
            fi
            fs_remove_rf "$target"
        fi

        # Create symlink
        fs_symlink "$last_layer" "$target"
        log_ok "Symlinked: $target"
        log_detail "-> $last_layer"

        hook_result_new __bms_result 1
        hook_result_add_file __bms_result "$target"
        return $E_OK
    else
        # Layer is a file - find config file and symlink
        local config_file
        local target_name
        target_name=$(basename "$target")

        # If layer is already a file, use it directly
        if fs_is_file "$last_layer"; then
            config_file="$last_layer"
        else
            config_file=$(_symlink_find_config_file "$last_layer" "$target_name")
        fi

        if [[ -z "$config_file" ]]; then
            hook_result_new_failure __bms_result $E_NOT_FOUND "Could not find config file in layer: $last_layer"
            return $E_NOT_FOUND
        fi

        # Backup existing target
        if fs_exists "$target"; then
            local backup_path=""
            if ! backup_create "$target" backup_path; then
                hook_result_new_failure __bms_result $E_BACKUP "Backup failed for: $target"
                return $E_BACKUP
            fi
            fs_remove "$target"
        fi

        # Create symlink
        fs_symlink "$config_file" "$target"
        log_ok "Symlinked: $target"
        log_detail "-> $config_file"

        hook_result_new __bms_result 1
        hook_result_add_file __bms_result "$target"
        return $E_OK
    fi
}
