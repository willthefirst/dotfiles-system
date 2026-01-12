#!/usr/bin/env bash
# MODULE: config/parser
# PURPOSE: Parse tool configuration files (JSON) into raw key-value associative arrays
#
# PUBLIC API:
#   config_parse_tool(tool_dir, result_ref)
#       Parse tool configuration from tool.json.
#       Returns E_OK, E_NOT_FOUND, or E_VALIDATION.
#
# DEPENDENCIES: core/fs.sh, core/errors.sh, jq

[[ -n "${_CONFIG_PARSER_LOADED:-}" ]] && return 0
_CONFIG_PARSER_LOADED=1

# Source dependencies
_CONFIG_PARSER_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONFIG_PARSER_DIR/../core/fs.sh"
source "$_CONFIG_PARSER_DIR/../core/errors.sh"

# Parse tool configuration from tool.json
# Usage: config_parse_tool "/path/to/tools/git" result
# Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
config_parse_tool() {
    local tool_dir="$1"
    local -n __cpt_result=$2

    _config_parse_tool_json "$tool_dir" __cpt_result
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
