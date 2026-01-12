#!/usr/bin/env bash
# MODULE: config/validator
# PURPOSE: Convert raw config to validated ToolConfig contract
#
# PUBLIC API:
#   config_build_tool_config(raw_ref, tool_config_ref, tool_dir)
#       Convert raw parsed config to validated ToolConfig.
#       Returns E_OK or E_VALIDATION.
#
#   config_resolve_hook_path(hook, tool_dir)
#       Resolve a hook specification to its full path.
#       Outputs resolved path to stdout.
#
#   config_parse_layer_spec(spec, source_ref, path_ref)
#       Parse a layer spec "source:path" into components.
#       Returns 0 on success, 1 on invalid format.
#
# DEPENDENCIES: core/errors.sh, contracts/tool_config.sh

[[ -n "${_CONFIG_VALIDATOR_LOADED:-}" ]] && return 0
_CONFIG_VALIDATOR_LOADED=1

# Source dependencies
_CONFIG_VALIDATOR_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONFIG_VALIDATOR_DIR/../core/errors.sh"
source "$_CONFIG_VALIDATOR_DIR/../contracts/tool_config.sh"

# Build a validated ToolConfig from raw parsed config
# Usage: config_build_tool_config raw_config tool_config "/path/to/tools/git"
# Returns: E_OK or E_VALIDATION
config_build_tool_config() {
    local -n __cbtc_raw=$1
    local -n __cbtc_result=$2
    local tool_dir="$3"

    local errors=()

    # Extract tool name from directory
    local tool_name
    tool_name=$(basename "$tool_dir")

    # Get required fields
    local target="${__cbtc_raw[target]:-}"
    local merge_hook="${__cbtc_raw[merge_hook]:-}"
    local install_hook="${__cbtc_raw[install_hook]:-}"

    # Check required fields
    [[ -z "$target" ]] && errors+=("target is required")
    [[ -z "$merge_hook" ]] && errors+=("merge_hook is required")

    # Resolve hook paths (relative to tool_dir or builtin:*)
    merge_hook=$(config_resolve_hook_path "$merge_hook" "$tool_dir")
    if [[ -n "$install_hook" ]]; then
        install_hook=$(config_resolve_hook_path "$install_hook" "$tool_dir")
    fi

    # Create the ToolConfig
    tool_config_new __cbtc_result "$tool_name" "$target" "$merge_hook"

    # Set install hook if present
    if [[ -n "$install_hook" ]]; then
        tool_config_set_install_hook __cbtc_result "$install_hook"
    fi

    # Process layer definitions (layers_* keys)
    local key
    for key in "${!__cbtc_raw[@]}"; do
        if [[ "$key" == layers_* ]]; then
            local layer_name="${key#layers_}"
            local layer_spec="${__cbtc_raw[$key]}"

            # Parse layer spec "source:path"
            local source path
            if config_parse_layer_spec "$layer_spec" source path; then
                tool_config_add_layer __cbtc_result "$layer_name" "$source" "$path"
            else
                errors+=("invalid layer spec for $layer_name: $layer_spec (expected source:path)")
            fi
        fi
    done

    # Report any parsing errors before validation
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'config/validator: build failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    # Validate the resulting ToolConfig
    if ! tool_config_validate __cbtc_result; then
        return $E_VALIDATION
    fi

    return $E_OK
}

# Resolve a hook specification to its full path
# Handles:
#   - "builtin:*" - returned as-is
#   - "./relative" - resolved relative to tool_dir
#   - "relative" - resolved relative to tool_dir
#   - "/absolute" - returned as-is
# Usage: config_resolve_hook_path "$hook" "$tool_dir"
config_resolve_hook_path() {
    local hook="$1"
    local tool_dir="$2"

    # Builtin hooks are returned as-is
    if [[ "$hook" == builtin:* ]]; then
        printf '%s' "$hook"
        return
    fi

    # Absolute paths are returned as-is
    if [[ "$hook" == /* ]]; then
        printf '%s' "$hook"
        return
    fi

    # Relative paths (./foo or just foo) are resolved relative to tool_dir
    if [[ "$hook" == ./* ]]; then
        printf '%s/%s' "$tool_dir" "${hook:2}"
    else
        printf '%s/%s' "$tool_dir" "$hook"
    fi
}

# Parse a layer spec in "source:path" format
# Usage: config_parse_layer_spec "local:configs/git" source_var path_var
# Returns: 0 on success, 1 on invalid format
config_parse_layer_spec() {
    local spec="$1"
    local -n __cpls_source=$2
    local -n __cpls_path=$3

    # Must contain a colon
    if [[ "$spec" != *:* ]]; then
        return 1
    fi

    # Split on first colon
    __cpls_source="${spec%%:*}"
    __cpls_path="${spec#*:}"

    # Both parts must be non-empty
    if [[ -z "$__cpls_source" || -z "$__cpls_path" ]]; then
        return 1
    fi

    return 0
}
