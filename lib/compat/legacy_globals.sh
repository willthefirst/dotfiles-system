#!/usr/bin/env bash
# MODULE: compat/legacy_globals
# PURPOSE: Provide TOOL_CTX and legacy globals during transition from old to new system
#
# This compatibility shim allows existing custom merge.sh scripts that may rely on
# TOOL_CTX or legacy globals to continue working during the migration period.
#
# PUBLIC API:
#   populate_legacy_globals(config_ref)  - Populate TOOL_CTX and legacy env vars from ToolConfig
#   clear_legacy_globals()               - Clear TOOL_CTX and legacy state
#
# USAGE:
#   In the orchestrator or runner, after building a ToolConfig:
#     source "lib/compat/legacy_globals.sh"
#     populate_legacy_globals tool_config
#
#   Custom merge scripts can then access:
#     - TOOL_CTX[target], TOOL_CTX[merge_hook], etc. (associative array)
#     - TOOL_TARGET, TOOL_MERGE_HOOK (simple variables)
#     - TOOL_LAYERS (associative array of layer specs)
#
# DEPRECATION:
#   This module is deprecated and will be removed in Phase 8.
#   New code should use environment variables (TOOL, TARGET, LAYERS, etc.)
#   which are set by executor/runner.sh.
#
# DEPENDENCIES:
#   contracts/tool_config.sh (for reading ToolConfig)

[[ -n "${_COMPAT_LEGACY_GLOBALS_LOADED:-}" ]] && return 0
_COMPAT_LEGACY_GLOBALS_LOADED=1

# Source dependencies for ToolConfig accessors
_COMPAT_DIR="${BASH_SOURCE[0]%/*}"
source "$_COMPAT_DIR/../contracts/tool_config.sh"

# ============================================================================
# Legacy Global State
# ============================================================================
# These mirror the old layers.sh globals

declare -gA TOOL_CTX
declare -gA TOOL_LAYERS
declare -gA TOOL_ENV

TOOL_TARGET=""
TOOL_INSTALL_HOOK=""
TOOL_MERGE_HOOK=""

# ============================================================================
# Public API
# ============================================================================

# Populate legacy globals from a ToolConfig
# Usage: populate_legacy_globals tool_config
# @deprecated Use environment variables set by runner.sh instead
populate_legacy_globals() {
    local -n __plg_config=$1

    # Clear previous state
    clear_legacy_globals

    # Populate TOOL_CTX from ToolConfig fields
    TOOL_CTX[tool_name]=$(tool_config_get_tool_name __plg_config)
    TOOL_CTX[target]=$(tool_config_get_target __plg_config)
    TOOL_CTX[merge_hook]=$(tool_config_get_merge_hook __plg_config)
    TOOL_CTX[install_hook]=$(tool_config_get_install_hook __plg_config)

    # Populate simple legacy variables
    TOOL_TARGET="${TOOL_CTX[target]}"
    TOOL_MERGE_HOOK="${TOOL_CTX[merge_hook]}"
    TOOL_INSTALL_HOOK="${TOOL_CTX[install_hook]}"

    # Populate TOOL_LAYERS from ToolConfig layers
    local layer_count
    layer_count=$(tool_config_get_layer_count __plg_config)

    local layer_keys=""
    local i
    for ((i = 0; i < layer_count; i++)); do
        local name source path
        name=$(tool_config_get_layer_name __plg_config "$i")
        source=$(tool_config_get_layer_source __plg_config "$i")
        path=$(tool_config_get_layer_path __plg_config "$i")

        # Store in TOOL_LAYERS with "source:path" format (original format)
        TOOL_LAYERS["$name"]="${source}:${path}"

        # Also store in TOOL_CTX with "layer:" prefix (used by ctx_get_layer)
        TOOL_CTX["layer:$name"]="${source}:${path}"

        if [[ -n "$layer_keys" ]]; then
            layer_keys+=" "
        fi
        layer_keys+="$name"
    done

    TOOL_CTX[_layer_keys]="$layer_keys"
}

# Clear all legacy global state
# Usage: clear_legacy_globals
clear_legacy_globals() {
    TOOL_CTX=()
    TOOL_LAYERS=()
    TOOL_ENV=()

    TOOL_CTX[target]=""
    TOOL_CTX[install_hook]=""
    TOOL_CTX[merge_hook]=""
    TOOL_CTX[_env_keys]=""
    TOOL_CTX[_layer_keys]=""

    TOOL_TARGET=""
    TOOL_INSTALL_HOOK=""
    TOOL_MERGE_HOOK=""
}

# ============================================================================
# Legacy Accessor Functions (for compatibility)
# ============================================================================
# These mirror the functions from old layers.sh

# Get a value from the tool context
# Usage: ctx_get "target"
# @deprecated Use environment variables instead
ctx_get() {
    echo "${TOOL_CTX[$1]:-}"
}

# Get a layer specification from context
# Usage: ctx_get_layer "base"
# @deprecated Use LAYER_PATHS environment variable instead
ctx_get_layer() {
    echo "${TOOL_CTX[layer:$1]:-}"
}

# Get an env var from context
# Usage: ctx_get_env "MY_VAR"
# @deprecated Use direct environment variable access instead
ctx_get_env() {
    echo "${TOOL_CTX[env:$1]:-}"
}

# Check if context has any env vars
# @deprecated
ctx_has_env_vars() {
    [[ -n "${TOOL_CTX[_env_keys]:-}" ]]
}

# Iterate over env vars in context
# @deprecated
ctx_env_keys() {
    echo "${TOOL_CTX[_env_keys]:-}"
}

# Initialize/reset the tool context
# @deprecated
init_tool_ctx() {
    clear_legacy_globals
}
