#!/usr/bin/env bash
# MODULE: config/parser
# PURPOSE: Parse tool configuration files (JSON or legacy conf) into raw key-value associative arrays
#
# PUBLIC API:
#   config_parse_tool(tool_dir, result_ref)
#       Parse tool configuration (JSON preferred, falls back to conf).
#       Returns E_OK, E_NOT_FOUND, or E_VALIDATION.
#
#   config_parse_tool_conf(tool_dir, result_ref)
#       Parse a tool.conf file from a tool directory.
#       Returns E_OK, E_NOT_FOUND, or E_VALIDATION.
#
#   config_parse_line(line, key_ref, value_ref)
#       Parse a single key=value line.
#       Returns 0 if parsed, 1 if skip (comment/empty), 2 if invalid.
#
# DEPENDENCIES: core/fs.sh, core/errors.sh

[[ -n "${_CONFIG_PARSER_LOADED:-}" ]] && return 0
_CONFIG_PARSER_LOADED=1

# Source dependencies
_CONFIG_PARSER_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONFIG_PARSER_DIR/../core/fs.sh"
source "$_CONFIG_PARSER_DIR/../core/errors.sh"

# Parse tool configuration (JSON preferred, falls back to conf)
# Usage: config_parse_tool "/path/to/tools/git" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
config_parse_tool() {
    local tool_dir="$1"
    local -n __cpt_result=$2

    # Try JSON first
    if _config_parse_tool_json "$tool_dir" __cpt_result; then
        return $E_OK
    fi

    # Fall back to legacy key=value format
    config_parse_tool_conf "$tool_dir" __cpt_result
}

# Parse tool.json file (internal function)
# Usage: _config_parse_tool_json "/path/to/tools/git" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
_config_parse_tool_json() {
    local tool_dir="$1"
    local -n __cptj_result=$2
    local json_path="${tool_dir}/tool.json"

    # Check if JSON file exists
    if ! fs_is_file "$json_path"; then
        return $E_NOT_FOUND
    fi

    # Read file content
    local content
    content=$(fs_read "$json_path") || return $E_NOT_FOUND

    # Validate JSON syntax
    if ! echo "$content" | jq . &>/dev/null; then
        echo "config/parser: invalid JSON in $json_path" >&2
        return $E_VALIDATION
    fi

    # Extract target (expand ~ to $HOME)
    local target
    target=$(echo "$content" | jq -r '.target // empty')
    if [[ -n "$target" ]]; then
        __cptj_result[target]="${target/#\~/$HOME}"
    fi

    # Extract merge_hook
    local merge_hook
    merge_hook=$(echo "$content" | jq -r '.merge_hook // empty')
    [[ -n "$merge_hook" ]] && __cptj_result[merge_hook]="$merge_hook"

    # Extract install_hook
    local install_hook
    install_hook=$(echo "$content" | jq -r '.install_hook // empty')
    [[ -n "$install_hook" ]] && __cptj_result[install_hook]="$install_hook"

    # Extract layers as layers_<name>=source:path for compatibility
    local i=0
    while true; do
        local layer_name layer_source layer_path
        layer_name=$(echo "$content" | jq -r ".layers[$i].name // empty")
        [[ -z "$layer_name" ]] && break
        layer_source=$(echo "$content" | jq -r ".layers[$i].source")
        layer_path=$(echo "$content" | jq -r ".layers[$i].path")
        __cptj_result["layers_${layer_name}"]="${layer_source}:${layer_path}"
        ((++i))
    done

    return $E_OK
}

# Parse a tool.conf file into raw key-value pairs
# Usage: config_parse_tool_conf "/path/to/tools/git" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
config_parse_tool_conf() {
    local tool_dir="$1"
    local -n __cptc_result=$2

    local conf_path="${tool_dir}/tool.conf"

    # Check if file exists
    if ! fs_is_file "$conf_path"; then
        return $E_NOT_FOUND
    fi

    # Read file content
    local content
    content=$(fs_read "$conf_path") || return $E_NOT_FOUND

    # Parse each line
    local line_num=0
    local key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        ((++line_num))

        local parse_result=0
        config_parse_line "$line" key value || parse_result=$?

        case $parse_result in
            0)  # Valid key=value
                __cptc_result["$key"]="$value"
                ;;
            1)  # Comment or empty - skip
                ;;
            2)  # Invalid line
                echo "config/parser: invalid line $line_num in $conf_path: $line" >&2
                return $E_VALIDATION
                ;;
        esac
    done <<< "$content"

    return $E_OK
}

# Parse a single configuration line
# Usage: config_parse_line "$line" key_var value_var
# Returns: 0 = valid key=value, 1 = skip (comment/empty), 2 = invalid
config_parse_line() {
    local line="$1"
    local -n __cpl_key=$2
    local -n __cpl_value=$3

    # Strip leading/trailing whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip empty lines
    [[ -z "$line" ]] && return 1

    # Skip comment lines
    [[ "$line" == \#* ]] && return 1

    # Must contain = for key=value
    if [[ "$line" != *=* ]]; then
        return 2
    fi

    # Extract key (everything before first =)
    __cpl_key="${line%%=*}"

    # Strip whitespace from key
    __cpl_key="${__cpl_key#"${__cpl_key%%[![:space:]]*}"}"
    __cpl_key="${__cpl_key%"${__cpl_key##*[![:space:]]}"}"

    # Validate key is non-empty and looks like an identifier
    if [[ -z "$__cpl_key" || ! "$__cpl_key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        return 2
    fi

    # Extract value (everything after first =)
    local raw_value="${line#*=}"

    # Strip leading whitespace from value
    raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"

    # Handle quoted values
    if [[ "$raw_value" == \"* ]]; then
        # Double-quoted: extract until closing quote
        # Handle inline comments after closing quote
        if [[ "$raw_value" =~ ^\"([^\"]*)\"(.*)$ ]]; then
            __cpl_value="${BASH_REMATCH[1]}"
        else
            # Unclosed quote - take everything between quotes if possible
            __cpl_value="${raw_value#\"}"
            __cpl_value="${__cpl_value%\"*}"
        fi
    elif [[ "$raw_value" == \'* ]]; then
        # Single-quoted: extract until closing quote (no expansion)
        if [[ "$raw_value" =~ ^\'([^\']*)\'(.*)$ ]]; then
            __cpl_value="${BASH_REMATCH[1]}"
        else
            __cpl_value="${raw_value#\'}"
            __cpl_value="${__cpl_value%\'*}"
        fi
    else
        # Unquoted: take until whitespace or # comment
        __cpl_value="${raw_value%%[[:space:]#]*}"
    fi

    # Expand ${VAR} and $VAR patterns for double-quoted and unquoted values
    # (single-quoted values should not be expanded, but we extracted before quote type check)
    if [[ "$raw_value" != \'* ]]; then
        __cpl_value=$(config_expand_vars "$__cpl_value")
    fi

    return 0
}

# Expand environment variables in a value
# Handles ${VAR}, ${VAR:-default}, and $VAR patterns
# Usage: config_expand_vars "string"
config_expand_vars() {
    local value="$1"
    local result="$value"
    local max_iterations=50
    local iteration=0

    # Expand ${VAR:-default} patterns first (more specific)
    while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*):-([^}]*)\} ]] && ((iteration++ < max_iterations)); do
        local var_name="${BASH_REMATCH[1]}"
        local default_value="${BASH_REMATCH[2]}"
        local var_value="${!var_name:-$default_value}"
        # Build the pattern to replace
        local pattern="\${${var_name}:-${default_value}}"
        result="${result/"$pattern"/$var_value}"
    done

    # Expand ${VAR} patterns
    iteration=0
    while [[ "$result" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)\} ]] && ((iteration++ < max_iterations)); do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        result="${result/\$\{$var_name\}/$var_value}"
    done

    # Expand $VAR patterns (not followed by more identifier chars)
    iteration=0
    while [[ "$result" =~ \$([A-Za-z_][A-Za-z0-9_]*) ]] && ((iteration++ < max_iterations)); do
        local var_name="${BASH_REMATCH[1]}"
        local var_value="${!var_name:-}"
        result="${result/\$$var_name/$var_value}"
    done

    printf '%s' "$result"
}
