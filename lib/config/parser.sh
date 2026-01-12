#!/usr/bin/env bash
# MODULE: config/parser
# PURPOSE: Parse tool.conf files into raw key-value associative arrays
#
# PUBLIC API:
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
# Handles ${VAR} and $VAR patterns
# Usage: config_expand_vars "string"
config_expand_vars() {
    local value="$1"
    local result=""
    local i=0
    local len=${#value}

    while ((i < len)); do
        local char="${value:i:1}"

        if [[ "$char" == '$' ]]; then
            # Check for ${VAR} pattern
            if [[ "${value:i:2}" == '${' ]]; then
                # Find closing }
                local end=$((i + 2))
                while ((end < len)) && [[ "${value:end:1}" != '}' ]]; do
                    ((end++))
                done

                if ((end < len)); then
                    local var_name="${value:i+2:end-i-2}"
                    local var_value="${!var_name:-}"
                    result+="$var_value"
                    i=$((end + 1))
                    continue
                fi
            fi

            # Check for $VAR pattern (alphanumeric + underscore)
            local var_start=$((i + 1))
            local var_end=$var_start
            while ((var_end < len)) && [[ "${value:var_end:1}" =~ [a-zA-Z0-9_] ]]; do
                ((var_end++))
            done

            if ((var_end > var_start)); then
                local var_name="${value:var_start:var_end-var_start}"
                local var_value="${!var_name:-}"
                result+="$var_value"
                i=$var_end
                continue
            fi
        fi

        result+="$char"
        ((i++))
    done

    printf '%s' "$result"
}
