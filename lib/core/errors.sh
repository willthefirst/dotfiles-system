#!/usr/bin/env bash
# MODULE: core/errors
# PURPOSE: Error codes and handling utilities
#
# PUBLIC API:
#   Error codes (constants):
#     E_OK=0              - Success
#     E_GENERIC=1         - Generic failure
#     E_INVALID_INPUT=2   - Invalid input/arguments
#     E_NOT_FOUND=3       - File/resource not found
#     E_PERMISSION=4      - Permission denied
#     E_VALIDATION=5      - Validation failed
#     E_DEPENDENCY=6      - Missing dependency
#     E_BACKUP=7          - Backup operation failed
#
#   error_message(code)   - Get human-readable message for code
#   error_die(code, msg)  - Log error and exit with code
#
# DEPENDENCIES: core/log.sh (optional, falls back to echo)

[[ -n "${_CORE_ERRORS_LOADED:-}" ]] && return 0
_CORE_ERRORS_LOADED=1

# --- Error Codes ---
readonly E_OK=0
readonly E_GENERIC=1
readonly E_INVALID_INPUT=2
readonly E_NOT_FOUND=3
readonly E_PERMISSION=4
readonly E_VALIDATION=5
readonly E_DEPENDENCY=6
readonly E_BACKUP=7

# --- Error Messages ---
declare -gA _ERROR_MESSAGES=(
    [0]="Success"
    [1]="Operation failed"
    [2]="Invalid input or arguments"
    [3]="File or resource not found"
    [4]="Permission denied"
    [5]="Validation failed"
    [6]="Missing required dependency"
    [7]="Backup operation failed"
)

# Get human-readable message for error code
# Usage: error_message $E_NOT_FOUND
# Returns: string message on stdout
error_message() {
    local code="$1"
    printf '%s' "${_ERROR_MESSAGES[$code]:-Unknown error (code: $code)}"
}

# Log error and exit with code
# Usage: error_die $E_NOT_FOUND "File not found: config.sh"
error_die() {
    local code="$1"
    local msg="$2"

    if type -t log_error &>/dev/null; then
        log_error "$msg"
    else
        echo "ERROR: $msg" >&2
    fi
    exit "$code"
}
