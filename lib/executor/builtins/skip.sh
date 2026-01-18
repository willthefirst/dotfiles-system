#!/usr/bin/env bash
# MODULE: executor/builtins/skip
# PURPOSE: Skip builtin - does nothing, returns success
#
# PUBLIC API:
#   builtin_skip(config_ref, result_ref)

[[ -n "${_BUILTIN_SKIP_LOADED:-}" ]] && return 0
_BUILTIN_SKIP_LOADED=1

# Skip strategy - does nothing and returns success
# Usage: builtin_skip config result
builtin_skip() {
    local -n __bs_result=$2
    hook_result_new __bs_result 1
    return $E_OK
}
