#!/usr/bin/env bash
# CONTRACT: ToolConfig
# PURPOSE: Tool configuration data structure and validation
#
# A ToolConfig represents a fully parsed tool configuration including
# the target path, merge hook, optional install hook, and list of layers.
#
# PUBLIC API:
#   tool_config_new(result_ref, tool_name, target, merge_hook)
#       Create a new ToolConfig with required fields.
#
#   tool_config_validate(config_ref)
#       Validate a ToolConfig. Returns E_OK or E_VALIDATION.
#       On failure, writes errors to stderr.
#
#   tool_config_set_install_hook(config_ref, hook)
#       Set optional install hook.
#
#   tool_config_add_layer(config_ref, name, source, path)
#       Add a layer to the config.
#
#   tool_config_set_layer_resolved(config_ref, index, resolved_path)
#       Set the resolved path for a layer at given index.
#
#   tool_config_get_tool_name(config_ref)
#   tool_config_get_target(config_ref)
#   tool_config_get_merge_hook(config_ref)
#   tool_config_get_install_hook(config_ref)
#   tool_config_get_layer_count(config_ref)
#   tool_config_get_layer_name(config_ref, index)
#   tool_config_get_layer_source(config_ref, index)
#   tool_config_get_layer_path(config_ref, index)
#   tool_config_get_layer_resolved(config_ref, index)
#
# DEPENDENCIES: core/errors.sh

[[ -n "${_CONTRACT_TOOL_CONFIG_LOADED:-}" ]] && return 0
_CONTRACT_TOOL_CONFIG_LOADED=1

# Source dependencies
_CONTRACT_TOOL_CONFIG_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONTRACT_TOOL_CONFIG_DIR/../core/errors.sh"

# Create a new ToolConfig
# Usage: tool_config_new result "git" "$HOME/.gitconfig" "builtin:symlink"
tool_config_new() {
    local -n __tc_result=$1
    local tool_name="$2"
    local target="$3"
    local merge_hook="$4"

    __tc_result=(
        [tool_name]="$tool_name"
        [target]="$target"
        [merge_hook]="$merge_hook"
        [install_hook]=""
        [layer_count]=0
    )
}

# Validate a ToolConfig
# Returns: E_OK if valid, E_VALIDATION if not (with errors to stderr)
tool_config_validate() {
    local -n __tc_config=$1
    local errors=()

    # Required fields
    [[ -z "${__tc_config[tool_name]:-}" ]] && errors+=("tool_name is required")
    [[ -z "${__tc_config[target]:-}" ]] && errors+=("target is required")
    [[ -z "${__tc_config[merge_hook]:-}" ]] && errors+=("merge_hook is required")

    # Validate tool_name: alphanumeric, hyphens, underscores
    local tool_name="${__tc_config[tool_name]:-}"
    if [[ -n "$tool_name" && ! "$tool_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        errors+=("tool_name must be alphanumeric with hyphens/underscores: $tool_name")
    fi

    # Validate target: must be absolute path (starts with / or ~)
    local target="${__tc_config[target]:-}"
    if [[ -n "$target" && "$target" != /* && "$target" != ~* ]]; then
        errors+=("target must be absolute path (start with / or ~): $target")
    fi

    # Validate merge_hook: must be builtin:* or look like a path
    local merge_hook="${__tc_config[merge_hook]:-}"
    if [[ -n "$merge_hook" ]]; then
        if [[ "$merge_hook" != builtin:* ]]; then
            # Should look like a path - at minimum contain no spaces or special chars
            if [[ "$merge_hook" =~ [[:space:]] ]]; then
                errors+=("merge_hook path cannot contain spaces: $merge_hook")
            fi
        fi
    fi

    # Validate install_hook if present (same rules as merge_hook)
    local install_hook="${__tc_config[install_hook]:-}"
    if [[ -n "$install_hook" ]]; then
        if [[ "$install_hook" != builtin:* && "$install_hook" =~ [[:space:]] ]]; then
            errors+=("install_hook path cannot contain spaces: $install_hook")
        fi
    fi

    # Validate layers
    local layer_count="${__tc_config[layer_count]:-0}"
    local i
    for ((i = 0; i < layer_count; i++)); do
        local name="${__tc_config[layer_${i}_name]:-}"
        local source="${__tc_config[layer_${i}_source]:-}"
        local path="${__tc_config[layer_${i}_path]:-}"

        [[ -z "$name" ]] && errors+=("layer $i: name is required")
        [[ -z "$source" ]] && errors+=("layer $i: source is required")
        [[ -z "$path" ]] && errors+=("layer $i: path is required")

        # Validate source format
        if [[ -n "$source" && "$source" != "local" && ! "$source" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            errors+=("layer $i: source must be 'local' or REPO_NAME: $source")
        fi

        # Validate path is relative
        if [[ -n "$path" && "$path" == /* ]]; then
            errors+=("layer $i: path must be relative: $path")
        fi
    done

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'ToolConfig validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Set optional install hook
tool_config_set_install_hook() {
    local -n __tc_config=$1
    __tc_config[install_hook]="$2"
}

# Add a layer to the config
# Usage: tool_config_add_layer config "base" "local" "configs/git"
tool_config_add_layer() {
    local -n __tc_config=$1
    local name="$2"
    local source="$3"
    local path="$4"

    local idx="${__tc_config[layer_count]}"
    __tc_config[layer_${idx}_name]="$name"
    __tc_config[layer_${idx}_source]="$source"
    __tc_config[layer_${idx}_path]="$path"
    __tc_config[layer_${idx}_resolved]=""
    __tc_config[layer_count]=$((idx + 1))
}

# Set resolved path for a layer
tool_config_set_layer_resolved() {
    local -n __tc_config=$1
    local idx="$2"
    local resolved="$3"
    __tc_config[layer_${idx}_resolved]="$resolved"
}

# Getters
tool_config_get_tool_name() {
    local -n __tc_config=$1
    printf '%s' "${__tc_config[tool_name]:-}"
}

tool_config_get_target() {
    local -n __tc_config=$1
    printf '%s' "${__tc_config[target]:-}"
}

tool_config_get_merge_hook() {
    local -n __tc_config=$1
    printf '%s' "${__tc_config[merge_hook]:-}"
}

tool_config_get_install_hook() {
    local -n __tc_config=$1
    printf '%s' "${__tc_config[install_hook]:-}"
}

tool_config_get_layer_count() {
    local -n __tc_config=$1
    printf '%s' "${__tc_config[layer_count]:-0}"
}

tool_config_get_layer_name() {
    local -n __tc_config=$1
    local idx="$2"
    printf '%s' "${__tc_config[layer_${idx}_name]:-}"
}

tool_config_get_layer_source() {
    local -n __tc_config=$1
    local idx="$2"
    printf '%s' "${__tc_config[layer_${idx}_source]:-}"
}

tool_config_get_layer_path() {
    local -n __tc_config=$1
    local idx="$2"
    printf '%s' "${__tc_config[layer_${idx}_path]:-}"
}

tool_config_get_layer_resolved() {
    local -n __tc_config=$1
    local idx="$2"
    printf '%s' "${__tc_config[layer_${idx}_resolved]:-}"
}
