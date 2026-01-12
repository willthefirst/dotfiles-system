#!/usr/bin/env bash
# MODULE: executor/builtins/json-merge
# PURPOSE: JSON merge strategy - deep merges JSON files from all layers
#
# PUBLIC API:
#   builtin_merge_json(config_ref, result_ref)
#       Deep merges JSON files from all layers using jq.
#       Later layers override earlier layers.
#
# DEPENDENCIES:
#   core/fs.sh, core/log.sh, core/backup.sh, core/errors.sh
#   contracts/tool_config.sh, contracts/hook_result.sh
#   External: jq

[[ -n "${_BUILTIN_JSON_MERGE_LOADED:-}" ]] && return 0
_BUILTIN_JSON_MERGE_LOADED=1

# Source dependencies
_BUILTIN_JSON_DIR="${BASH_SOURCE[0]%/*}"
source "$_BUILTIN_JSON_DIR/../../core/fs.sh"
source "$_BUILTIN_JSON_DIR/../../core/log.sh"
source "$_BUILTIN_JSON_DIR/../../core/backup.sh"
source "$_BUILTIN_JSON_DIR/../../core/errors.sh"
source "$_BUILTIN_JSON_DIR/../../contracts/tool_config.sh"
source "$_BUILTIN_JSON_DIR/../../contracts/hook_result.sh"

# Find a JSON config file within a layer directory
# Usage: _json_find_config_file layer_path target_name
_json_find_config_file() {
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

    # Candidate files in priority order (prefer .json files)
    local candidates=(
        "$layer_path/$target_name"
        "$layer_path/config.json"
        "$layer_path/${target_name%.json}.json"
        "$layer_path/config"
    )

    for candidate in "${candidates[@]}"; do
        if fs_is_file "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done

    # Fallback: first .json file in directory
    if [[ "$(fs_get_backend)" == "mock" ]]; then
        local files
        files=$(fs_list "$layer_path")
        if [[ -n "$files" ]]; then
            # Try to find a .json file first
            local json_file
            json_file=$(echo "$files" | grep '\.json$' | head -1)
            if [[ -n "$json_file" ]] && fs_is_file "$layer_path/$json_file"; then
                printf '%s' "$layer_path/$json_file"
                return 0
            fi
            # Otherwise, use first file
            local first
            first=$(echo "$files" | head -1)
            if [[ -n "$first" ]] && fs_is_file "$layer_path/$first"; then
                printf '%s' "$layer_path/$first"
                return 0
            fi
        fi
    else
        local first_file
        first_file=$(find "$layer_path" -maxdepth 1 -type f -name "*.json" 2>/dev/null | head -1)
        if [[ -n "$first_file" ]]; then
            printf '%s' "$first_file"
            return 0
        fi
        # Try any file if no .json found
        first_file=$(find "$layer_path" -maxdepth 1 -type f 2>/dev/null | head -1)
        if [[ -n "$first_file" ]]; then
            printf '%s' "$first_file"
            return 0
        fi
    fi

    return 1
}

# Deep merge two JSON strings using jq
# Usage: _json_deep_merge "$base_json" "$overlay_json"
_json_deep_merge() {
    local base="$1"
    local overlay="$2"

    # In mock mode, do a simple simulation
    if [[ "$(fs_get_backend)" == "mock" ]]; then
        # For testing, just concatenate (tests should validate structure separately)
        # Real mode would use jq
        if [[ -z "$base" || "$base" == "{}" ]]; then
            printf '%s' "$overlay"
        elif [[ -z "$overlay" || "$overlay" == "{}" ]]; then
            printf '%s' "$base"
        else
            # Simple mock merge - just return overlay (simulates override behavior)
            printf '%s' "$overlay"
        fi
        return 0
    fi

    # Real mode - use jq for deep merge
    echo "$base" | jq -s --argjson overlay "$overlay" '.[0] * $overlay' 2>/dev/null
}

# JSON merge strategy
# Usage: builtin_merge_json config result
builtin_merge_json() {
    local -n __bmj_config=$1
    local -n __bmj_result=$2

    # Check for jq dependency (in real mode)
    if [[ "$(fs_get_backend)" == "real" ]]; then
        if ! command -v jq &>/dev/null; then
            hook_result_new_failure __bmj_result $E_DEPENDENCY "jq is required for JSON merging but not found"
            return $E_DEPENDENCY
        fi
    fi

    local layer_count
    layer_count=$(tool_config_get_layer_count __bmj_config)

    if [[ $layer_count -eq 0 ]]; then
        hook_result_new_failure __bmj_result $E_INVALID_INPUT "No layers defined"
        return $E_INVALID_INPUT
    fi

    # Get target path
    local target
    target=$(tool_config_get_target __bmj_config)
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
            hook_result_new_failure __bmj_result $E_BACKUP "Backup failed for: $target"
            return $E_BACKUP
        fi
        fs_remove "$target"
    fi

    # Start with empty JSON object
    local merged="{}"
    local layers_found=0

    # Merge all layers
    local i
    for ((i = 0; i < layer_count; i++)); do
        local layer_name
        layer_name=$(tool_config_get_layer_name __bmj_config "$i")
        local layer_path
        layer_path=$(tool_config_get_layer_resolved __bmj_config "$i")

        if [[ -z "$layer_path" ]]; then
            log_warn "Layer $layer_name: not resolved"
            continue
        fi

        # Find JSON config file in layer
        local config_file
        config_file=$(_json_find_config_file "$layer_path" "$target_name") || true

        if [[ -n "$config_file" ]] && fs_is_file "$config_file"; then
            local layer_json
            layer_json=$(fs_read "$config_file")

            # Validate JSON (in real mode)
            if [[ "$(fs_get_backend)" == "real" ]]; then
                if ! echo "$layer_json" | jq . &>/dev/null; then
                    log_warn "Invalid JSON in layer: $config_file"
                    continue
                fi
            fi

            # Deep merge
            merged=$(_json_deep_merge "$merged" "$layer_json")
            log_detail "Merged: $layer_name"
            ((layers_found++)) || true
        else
            log_warn "No JSON config file in layer: $layer_path"
        fi
    done

    if [[ $layers_found -eq 0 ]]; then
        hook_result_new_failure __bmj_result $E_NOT_FOUND "No JSON config files found in any layer"
        return $E_NOT_FOUND
    fi

    # Pretty print the result (in real mode)
    if [[ "$(fs_get_backend)" == "real" ]]; then
        merged=$(echo "$merged" | jq '.')
    fi

    # Write merged JSON
    fs_write "$target" "$merged"

    log_ok "Merged JSON written: $target"

    hook_result_new __bmj_result 1
    hook_result_add_file __bmj_result "$target"
    return $E_OK
}
