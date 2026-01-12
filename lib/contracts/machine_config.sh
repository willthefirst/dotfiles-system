#!/usr/bin/env bash
# CONTRACT: MachineConfig
# PURPOSE: Machine profile data structure and validation
#
# A MachineConfig represents a loaded machine profile, specifying which
# tools to configure and which layers each tool should use.
#
# PUBLIC API:
#   machine_config_new(result_ref, profile_name)
#       Create a new MachineConfig.
#
#   machine_config_validate(config_ref)
#       Validate a MachineConfig. Returns E_OK or E_VALIDATION.
#       On failure, writes errors to stderr.
#
#   machine_config_add_tool(config_ref, tool_name)
#       Add a tool to the config.
#
#   machine_config_set_tool_layers(config_ref, tool_name, layers)
#       Set layers for a tool (space-separated layer names).
#
#   machine_config_get_profile_name(config_ref)
#   machine_config_get_tool_count(config_ref)
#   machine_config_get_tool(config_ref, index)
#   machine_config_get_tool_layers(config_ref, tool_name)
#   machine_config_has_tool(config_ref, tool_name)
#
# DEPENDENCIES: core/errors.sh

[[ -n "${_CONTRACT_MACHINE_CONFIG_LOADED:-}" ]] && return 0
_CONTRACT_MACHINE_CONFIG_LOADED=1

# Source dependencies
_CONTRACT_MACHINE_CONFIG_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONTRACT_MACHINE_CONFIG_DIR/../core/errors.sh"

# Create a new MachineConfig
# Usage: machine_config_new result "work-macbook"
machine_config_new() {
    local -n __mc_result=$1
    local profile_name="$2"

    __mc_result=(
        [profile_name]="$profile_name"
        [tool_count]=0
    )
}

# Validate a MachineConfig
# Returns: E_OK if valid, E_VALIDATION if not (with errors to stderr)
machine_config_validate() {
    local -n __mc_config=$1
    local errors=()

    # Required fields
    [[ -z "${__mc_config[profile_name]:-}" ]] && errors+=("profile_name is required")

    # Validate profile_name: alphanumeric, hyphens, underscores
    local profile_name="${__mc_config[profile_name]:-}"
    if [[ -n "$profile_name" && ! "$profile_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        errors+=("profile_name must be alphanumeric with hyphens/underscores: $profile_name")
    fi

    # Validate tools
    local tool_count="${__mc_config[tool_count]:-0}"
    local i
    for ((i = 0; i < tool_count; i++)); do
        local tool="${__mc_config[tool_${i}]:-}"
        [[ -z "$tool" ]] && errors+=("tool at index $i is empty")

        # Validate tool name format
        if [[ -n "$tool" && ! "$tool" =~ ^[a-zA-Z0-9_-]+$ ]]; then
            errors+=("tool name must be alphanumeric with hyphens/underscores: $tool")
        fi

        # Check layers exist for this tool
        local layers_key="layers_${tool}"
        if [[ -z "${__mc_config[$layers_key]+set}" ]]; then
            errors+=("no layers defined for tool: $tool")
        fi
    done

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'MachineConfig validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Add a tool to the config
# Usage: machine_config_add_tool config "git"
machine_config_add_tool() {
    local -n __mc_config=$1
    local tool_name="$2"

    local idx="${__mc_config[tool_count]}"
    __mc_config[tool_${idx}]="$tool_name"
    __mc_config[tool_count]=$((idx + 1))
}

# Set layers for a tool
# Usage: machine_config_set_tool_layers config "git" "base work"
machine_config_set_tool_layers() {
    local -n __mc_config=$1
    local tool_name="$2"
    local layers="$3"

    __mc_config[layers_${tool_name}]="$layers"
}

# Getters
machine_config_get_profile_name() {
    local -n __mc_config=$1
    printf '%s' "${__mc_config[profile_name]:-}"
}

machine_config_get_tool_count() {
    local -n __mc_config=$1
    printf '%s' "${__mc_config[tool_count]:-0}"
}

machine_config_get_tool() {
    local -n __mc_config=$1
    local idx="$2"
    printf '%s' "${__mc_config[tool_${idx}]:-}"
}

machine_config_get_tool_layers() {
    local -n __mc_config=$1
    local tool_name="$2"
    printf '%s' "${__mc_config[layers_${tool_name}]:-}"
}

# Check if tool exists in config
machine_config_has_tool() {
    local -n __mc_config=$1
    local tool_name="$2"

    local tool_count="${__mc_config[tool_count]:-0}"
    local i
    for ((i = 0; i < tool_count; i++)); do
        if [[ "${__mc_config[tool_${i}]:-}" == "$tool_name" ]]; then
            return 0
        fi
    done
    return 1
}
