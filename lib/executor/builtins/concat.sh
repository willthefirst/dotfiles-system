#!/usr/bin/env bash
# MODULE: executor/builtins/concat
# PURPOSE: Concatenate merge strategy - concatenates all layers into target
#
# PUBLIC API:
#   builtin_merge_concat(config_ref, result_ref)
#       Concatenates all layer files into the target, with layer headers.
#
# DEPENDENCIES:
#   core/fs.sh, core/log.sh, core/backup.sh, core/errors.sh
#   contracts/tool_config.sh, contracts/hook_result.sh

[[ -n "${_BUILTIN_CONCAT_LOADED:-}" ]] && return 0
_BUILTIN_CONCAT_LOADED=1

# Source dependencies
_BUILTIN_CONCAT_DIR="${BASH_SOURCE[0]%/*}"
source "$_BUILTIN_CONCAT_DIR/../../core/fs.sh"
source "$_BUILTIN_CONCAT_DIR/../../core/log.sh"
source "$_BUILTIN_CONCAT_DIR/../../core/backup.sh"
source "$_BUILTIN_CONCAT_DIR/../../core/errors.sh"
source "$_BUILTIN_CONCAT_DIR/../../contracts/tool_config.sh"
source "$_BUILTIN_CONCAT_DIR/../../contracts/hook_result.sh"

# Find a config file within a layer directory
# Usage: _concat_find_config_file layer_path target_name
_concat_find_config_file() {
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

    # Fallback: first file in directory
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

# Concatenate merge strategy
# Usage: builtin_merge_concat config result
builtin_merge_concat() {
    local -n __bmc_config=$1
    local -n __bmc_result=$2

    local layer_count
    layer_count=$(tool_config_get_layer_count __bmc_config)

    if [[ $layer_count -eq 0 ]]; then
        hook_result_new_failure __bmc_result $E_INVALID_INPUT "No layers defined"
        return $E_INVALID_INPUT
    fi

    # Get target path
    local target
    target=$(tool_config_get_target __bmc_config)
    # Expand tilde
    if [[ "$target" == "~"* ]]; then
        target="${target/#\~/$HOME}"
    fi

    local target_parent
    target_parent=$(dirname "$target")
    local target_name
    target_name=$(basename "$target")

    # Ensure parent directory exists
    fs_mkdir "$target_parent"

    # Backup existing target
    if fs_exists "$target"; then
        local backup_path=""
        if ! backup_create "$target" backup_path; then
            hook_result_new_failure __bmc_result $E_BACKUP "Backup failed for: $target"
            return $E_BACKUP
        fi
        fs_remove "$target"
    fi

    # Start with empty content
    local content=""
    local layers_found=0

    # Concatenate all layers
    local i
    for ((i = 0; i < layer_count; i++)); do
        local layer_name
        layer_name=$(tool_config_get_layer_name __bmc_config "$i")
        local layer_path
        layer_path=$(tool_config_get_layer_resolved __bmc_config "$i")

        if [[ -z "$layer_path" ]]; then
            log_warn "Layer $layer_name: not resolved"
            continue
        fi

        # Find config file in layer
        local config_file
        config_file=$(_concat_find_config_file "$layer_path" "$target_name") || true

        if [[ -n "$config_file" ]] && fs_is_file "$config_file"; then
            local layer_content
            layer_content=$(fs_read "$config_file")

            # Add layer header and content
            content+="# === Layer: $layer_name ===
# Source: $config_file

$layer_content

"
            log_detail "Appended: $layer_name"
            ((layers_found++)) || true
        else
            log_warn "No config file in layer: $layer_path"
        fi
    done

    if [[ $layers_found -eq 0 ]]; then
        hook_result_new_failure __bmc_result $E_NOT_FOUND "No config files found in any layer"
        return $E_NOT_FOUND
    fi

    # Write concatenated content
    fs_write "$target" "$content"

    log_ok "Concatenated config written: $target"

    hook_result_new __bmc_result 1
    hook_result_add_file __bmc_result "$target"
    return $E_OK
}
