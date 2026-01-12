#!/usr/bin/env bash
# MODULE: executor/registry
# PURPOSE: Strategy registration and lookup for merge/install hooks
#
# PUBLIC API:
#   strategy_register(name, handler)   - Register a strategy handler function
#   strategy_exists(name)              - Check if strategy is registered (0=yes, 1=no)
#   strategy_get(name)                 - Get handler function name for strategy
#   strategy_list()                    - List all registered strategy names
#   strategy_unregister(name)          - Remove a registered strategy
#   strategy_clear()                   - Clear all registered strategies
#
# DEPENDENCIES: core/errors.sh

[[ -n "${_EXECUTOR_REGISTRY_LOADED:-}" ]] && return 0
_EXECUTOR_REGISTRY_LOADED=1

# Source dependencies
_EXECUTOR_REGISTRY_DIR="${BASH_SOURCE[0]%/*}"
source "$_EXECUTOR_REGISTRY_DIR/../core/errors.sh"

# --- State ---
declare -gA _strategy_registry=()

# --- Public API ---

# Register a strategy handler
# Usage: strategy_register "symlink" "builtin_merge_symlink"
strategy_register() {
    local name="$1"
    local handler="$2"

    if [[ -z "$name" ]]; then
        echo "strategy_register: name is required" >&2
        return $E_INVALID_INPUT
    fi

    if [[ -z "$handler" ]]; then
        echo "strategy_register: handler is required" >&2
        return $E_INVALID_INPUT
    fi

    _strategy_registry["$name"]="$handler"
    return $E_OK
}

# Check if a strategy is registered
# Usage: strategy_exists "symlink" && echo "exists"
strategy_exists() {
    local name="$1"
    [[ -n "${_strategy_registry[$name]+set}" ]]
}

# Get the handler function for a strategy
# Usage: handler=$(strategy_get "symlink")
strategy_get() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    if ! strategy_exists "$name"; then
        echo "strategy_get: unknown strategy: $name" >&2
        return $E_NOT_FOUND
    fi

    printf '%s' "${_strategy_registry[$name]}"
    return $E_OK
}

# List all registered strategy names
# Usage: strategy_list  # outputs one per line
strategy_list() {
    for name in "${!_strategy_registry[@]}"; do
        echo "$name"
    done
}

# Remove a registered strategy
# Usage: strategy_unregister "symlink"
strategy_unregister() {
    local name="$1"

    if [[ -z "$name" ]]; then
        return $E_INVALID_INPUT
    fi

    if ! strategy_exists "$name"; then
        return $E_NOT_FOUND
    fi

    unset "_strategy_registry[$name]"
    return $E_OK
}

# Clear all registered strategies
# Usage: strategy_clear
strategy_clear() {
    _strategy_registry=()
    return $E_OK
}

# Get count of registered strategies
# Usage: count=$(strategy_count)
strategy_count() {
    echo "${#_strategy_registry[@]}"
}
