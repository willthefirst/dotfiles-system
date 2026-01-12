#!/usr/bin/env bash
# MODULE: config/machine
# PURPOSE: Load machine profiles (JSON) into MachineConfig contracts
#
# PUBLIC API:
#   config_load_machine_profile(profile_path, result_ref)
#       Load a machine profile from JSON into MachineConfig.
#       Returns E_OK, E_NOT_FOUND, or E_VALIDATION.
#
#   config_get_profile_name(profile_path)
#       Extract profile name from path.
#       Outputs name to stdout.
#
# DEPENDENCIES: core/fs.sh, core/errors.sh, contracts/machine_config.sh, jq

[[ -n "${_CONFIG_MACHINE_LOADED:-}" ]] && return 0
_CONFIG_MACHINE_LOADED=1

# Source dependencies
_CONFIG_MACHINE_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONFIG_MACHINE_DIR/../core/fs.sh"
source "$_CONFIG_MACHINE_DIR/../core/errors.sh"
source "$_CONFIG_MACHINE_DIR/../contracts/machine_config.sh"

# Load a machine profile from JSON into MachineConfig
# Usage: config_load_machine_profile "/path/to/machines/stripe-mac.json" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
config_load_machine_profile() {
    local profile_path="$1"
    local -n __clmp_result=$2

    # Check if file exists
    if ! fs_is_file "$profile_path"; then
        return $E_NOT_FOUND
    fi

    _machine_load_json "$profile_path" __clmp_result
}

# Load machine profile from JSON file
# Usage: _machine_load_json "/path/to/machines/stripe-mac.json" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
_machine_load_json() {
    local json_path="$1"
    local -n __mlj_result=$2

    # Read file content
    local content
    content=$(fs_read "$json_path") || return $E_NOT_FOUND

    # Validate JSON syntax
    if ! echo "$content" | jq . &>/dev/null; then
        echo "config/machine: invalid JSON in $json_path" >&2
        return $E_VALIDATION
    fi

    # Extract profile name from JSON (or fall back to filename)
    local profile_name
    profile_name=$(echo "$content" | jq -r '.name // empty')
    if [[ -z "$profile_name" ]]; then
        profile_name=$(config_get_profile_name "$json_path")
    fi

    # Create the MachineConfig
    machine_config_new __mlj_result "$profile_name"

    # Extract tools and their layers from the tools object
    local tools
    tools=$(echo "$content" | jq -r '.tools | keys[]' 2>/dev/null) || {
        echo "config/machine: no tools object in $json_path" >&2
        return $E_VALIDATION
    }

    if [[ -z "$tools" ]]; then
        echo "config/machine: tools object is empty in $json_path" >&2
        return $E_VALIDATION
    fi

    local tool
    for tool in $tools; do
        machine_config_add_tool __mlj_result "$tool"

        # Get layers array for this tool and join with spaces
        local layers
        layers=$(echo "$content" | jq -r ".tools[\"$tool\"] | join(\" \")")
        machine_config_set_tool_layers __mlj_result "$tool" "$layers"
    done

    # Validate the resulting MachineConfig
    if ! machine_config_validate __mlj_result; then
        return $E_VALIDATION
    fi

    return $E_OK
}

# Extract profile name from path
# Example: "machines/stripe-mac.json" -> "stripe-mac"
# Usage: config_get_profile_name "/path/to/machines/stripe-mac.json"
config_get_profile_name() {
    local profile_path="$1"

    # Get basename without .json extension
    local basename
    basename=$(basename "$profile_path")
    basename="${basename%.json}"

    printf '%s' "$basename"
}
