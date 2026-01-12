#!/usr/bin/env bash
# MODULE: config/machine
# PURPOSE: Load machine profiles into MachineConfig contracts
#
# PUBLIC API:
#   config_load_machine_profile(profile_path, result_ref)
#       Load a machine profile into MachineConfig.
#       Returns E_OK, E_NOT_FOUND, or E_VALIDATION.
#
#   config_get_profile_name(profile_path)
#       Extract profile name from path.
#       Outputs name to stdout.
#
#   config_parse_bash_array(content, array_name)
#       Parse a bash array definition from content.
#       Outputs space-separated values to stdout.
#
# DEPENDENCIES: core/fs.sh, core/errors.sh, contracts/machine_config.sh

[[ -n "${_CONFIG_MACHINE_LOADED:-}" ]] && return 0
_CONFIG_MACHINE_LOADED=1

# Source dependencies
_CONFIG_MACHINE_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONFIG_MACHINE_DIR/../core/fs.sh"
source "$_CONFIG_MACHINE_DIR/../core/errors.sh"
source "$_CONFIG_MACHINE_DIR/../contracts/machine_config.sh"

# Load a machine profile into MachineConfig
# Usage: config_load_machine_profile "/path/to/machines/stripe-mac.sh" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
config_load_machine_profile() {
    local profile_path="$1"
    local -n __clmp_result=$2

    # Check if file exists
    if ! fs_is_file "$profile_path"; then
        return $E_NOT_FOUND
    fi

    # Read file content
    local content
    content=$(fs_read "$profile_path") || return $E_NOT_FOUND

    # Extract profile name from path
    local profile_name
    profile_name=$(config_get_profile_name "$profile_path")

    # Create the MachineConfig
    machine_config_new __clmp_result "$profile_name"

    # Parse TOOLS array
    local tools_str
    tools_str=$(config_parse_bash_array "$content" "TOOLS")

    if [[ -z "$tools_str" ]]; then
        echo "config/machine: TOOLS array not found in $profile_path" >&2
        return $E_VALIDATION
    fi

    # Add each tool and its layers
    local tool
    for tool in $tools_str; do
        machine_config_add_tool __clmp_result "$tool"

        # Parse {tool}_layers array
        local layers_str
        layers_str=$(config_parse_bash_array "$content" "${tool}_layers")

        if [[ -n "$layers_str" ]]; then
            machine_config_set_tool_layers __clmp_result "$tool" "$layers_str"
        else
            # Default to empty layers (will fail validation)
            machine_config_set_tool_layers __clmp_result "$tool" ""
        fi
    done

    # Validate the resulting MachineConfig
    if ! machine_config_validate __clmp_result; then
        return $E_VALIDATION
    fi

    return $E_OK
}

# Extract profile name from path
# Example: "machines/stripe-mac.sh" -> "stripe-mac"
# Usage: config_get_profile_name "/path/to/machines/stripe-mac.sh"
config_get_profile_name() {
    local profile_path="$1"

    # Get basename without extension
    local basename
    basename=$(basename "$profile_path")
    basename="${basename%.sh}"

    printf '%s' "$basename"
}

# Parse a bash array definition from content
# Handles formats:
#   ARRAY=(foo bar baz)
#   ARRAY=(
#       foo
#       bar
#   )
# Usage: config_parse_bash_array "$content" "TOOLS"
# Outputs: space-separated values
config_parse_bash_array() {
    local content="$1"
    local array_name="$2"

    # Strategy: Extract everything between ARRAY_NAME=( and the matching )
    # Handle both single-line and multi-line formats

    local result=""
    local in_array=0
    local paren_depth=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Strip comments (but be careful of # inside quotes - simplified approach)
        local stripped="${line%%#*}"

        if [[ $in_array -eq 0 ]]; then
            # Look for array start: NAME=(
            if [[ "$stripped" =~ ^[[:space:]]*${array_name}[[:space:]]*=\( ]]; then
                in_array=1
                paren_depth=1

                # Extract content after opening paren on same line
                local after_paren="${stripped#*=\(}"

                # Check if closing paren is on same line
                if [[ "$after_paren" == *\)* ]]; then
                    # Single line array: extract between ( and )
                    after_paren="${after_paren%\)*}"
                    result+=" $after_paren"
                    in_array=0
                else
                    result+=" $after_paren"
                fi
            fi
        else
            # Inside array - look for closing paren
            if [[ "$stripped" == *\)* ]]; then
                # Found closing paren
                local before_paren="${stripped%\)*}"
                result+=" $before_paren"
                in_array=0
            else
                result+=" $stripped"
            fi
        fi
    done <<< "$content"

    # Clean up result: remove quotes, extra whitespace
    result=$(echo "$result" | tr '\n' ' ' | sed 's/["\x27]//g' | tr -s ' ')

    # Trim leading/trailing whitespace
    result="${result#"${result%%[![:space:]]*}"}"
    result="${result%"${result##*[![:space:]]}"}"

    printf '%s' "$result"
}
