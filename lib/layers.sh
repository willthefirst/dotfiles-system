#!/usr/bin/env bash
# lib/layers.sh
# Resolve layer specifications to absolute paths

set -euo pipefail

# Parse a tool.conf file and extract configuration
# Usage: parse_tool_conf "/path/to/tool.conf"
# Returns: Sets variables via eval (target, install_hook, merge_hook, env vars)
parse_tool_conf() {
    local tool_conf="$1"

    if [[ ! -f "$tool_conf" ]]; then
        echo "[ERROR] tool.conf not found: $tool_conf" >&2
        return 1
    fi

    # Initialize defaults
    TOOL_TARGET=""
    TOOL_INSTALL_HOOK=""
    TOOL_MERGE_HOOK=""
    declare -gA TOOL_LAYERS
    declare -gA TOOL_ENV

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Parse key="value" or key=value
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Remove quotes if present
            value="${value#\"}"
            value="${value%\"}"

            # Expand environment variables
            value=$(eval echo "$value")

            case "$key" in
                target)
                    TOOL_TARGET="$value"
                    ;;
                install_hook)
                    TOOL_INSTALL_HOOK="$value"
                    ;;
                merge_hook)
                    TOOL_MERGE_HOOK="$value"
                    ;;
                layers_*)
                    local layer_name="${key#layers_}"
                    TOOL_LAYERS["$layer_name"]="$value"
                    ;;
                env_*)
                    local env_name="${key#env_}"
                    TOOL_ENV["$env_name"]="$value"
                    ;;
            esac
        fi
    done < "$tool_conf"
}

# Resolve a single layer specification to an absolute path
# Usage: resolve_layer_path "local:base" "/path/to/dotfiles" "nvim"
# Returns: Absolute path to the layer directory
resolve_layer_path() {
    local layer_spec="$1"
    local dotfiles_dir="$2"
    local tool="$3"

    local repo_name="${layer_spec%%:*}"
    local layer_path="${layer_spec#*:}"

    if [[ "$repo_name" == "local" ]]; then
        # Local layer - relative to dotfiles root
        echo "${dotfiles_dir}/${layer_path}"
    else
        # External repo layer
        local repo_path
        repo_path=$(get_repo_path "$repo_name")

        if [[ -z "$repo_path" ]]; then
            echo "[ERROR] Unknown repository: $repo_name" >&2
            return 1
        fi

        echo "${repo_path}/${layer_path}"
    fi
}

# Resolve all layers for a tool given a list of layer names
# Usage: resolve_layers "nvim" "base:work" "/path/to/dotfiles"
# Returns: Colon-separated absolute paths
resolve_layers() {
    local tool="$1"
    local layer_names="$2"
    local dotfiles_dir="$3"

    local tool_conf="${dotfiles_dir}/tools/${tool}/tool.conf"

    if [[ ! -f "$tool_conf" ]]; then
        echo "[ERROR] No tool.conf found for: $tool" >&2
        return 1
    fi

    # Parse tool.conf to get layer definitions
    parse_tool_conf "$tool_conf"

    local resolved_paths=()
    IFS=':' read -ra names <<< "$layer_names"

    for name in "${names[@]}"; do
        local layer_spec="${TOOL_LAYERS[$name]:-}"

        if [[ -z "$layer_spec" ]]; then
            echo "[ERROR] Layer not defined in tool.conf: $name" >&2
            return 1
        fi

        local resolved_path
        resolved_path=$(resolve_layer_path "$layer_spec" "$dotfiles_dir" "$tool")

        if [[ ! -d "$resolved_path" ]]; then
            echo "[WARN] Layer directory does not exist: $resolved_path" >&2
        fi

        resolved_paths+=("$resolved_path")
    done

    # Join with colons
    local IFS=':'
    echo "${resolved_paths[*]}"
}

# Get layers for a tool from machine profile
# Usage: get_tool_layers "nvim" (requires machine profile to be sourced)
get_tool_layers() {
    local tool="$1"
    local var_name="${tool}_layers[@]"

    # Check if the array exists
    if declare -p "${tool}_layers" &>/dev/null 2>&1; then
        local layers
        eval "layers=(\"\${${tool}_layers[@]}\")"
        local IFS=':'
        echo "${layers[*]}"
    else
        # Default to base layer if not specified
        echo "base"
    fi
}

# Validate that all required layers exist
# Usage: validate_layers "nvim" "base:work" "/path/to/dotfiles"
validate_layers() {
    local tool="$1"
    local layer_names="$2"
    local dotfiles_dir="$3"

    local resolved_paths
    resolved_paths=$(resolve_layers "$tool" "$layer_names" "$dotfiles_dir")

    IFS=':' read -ra paths <<< "$resolved_paths"
    local missing=()

    for path in "${paths[@]}"; do
        if [[ ! -d "$path" ]]; then
            missing+=("$path")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[ERROR] Missing layer directories:" >&2
        for path in "${missing[@]}"; do
            echo "  - $path" >&2
        done
        return 1
    fi

    return 0
}
