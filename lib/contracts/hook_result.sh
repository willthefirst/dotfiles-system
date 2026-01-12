#!/usr/bin/env bash
# CONTRACT: HookResult
# PURPOSE: Hook execution result data structure and validation
#
# A HookResult represents the outcome of executing a merge or install hook,
# including success status, error information, and list of modified files.
#
# PUBLIC API:
#   hook_result_new(result_ref, success)
#       Create a new HookResult. success should be 1 (true) or 0 (false).
#
#   hook_result_new_failure(result_ref, error_code, error_message)
#       Create a new failed HookResult with error details.
#
#   hook_result_validate(result_ref)
#       Validate a HookResult. Returns E_OK or E_VALIDATION.
#       On failure, writes errors to stderr.
#
#   hook_result_set_error(result_ref, code, message)
#       Set error code and message (implies success=0).
#
#   hook_result_add_file(result_ref, path)
#       Add a modified file path to the result.
#
#   hook_result_is_success(result_ref)
#       Returns 0 if success, 1 otherwise.
#
#   hook_result_get_error_code(result_ref)
#   hook_result_get_error_message(result_ref)
#   hook_result_get_files_modified(result_ref)
#
# DEPENDENCIES: core/errors.sh

[[ -n "${_CONTRACT_HOOK_RESULT_LOADED:-}" ]] && return 0
_CONTRACT_HOOK_RESULT_LOADED=1

# Source dependencies
_CONTRACT_HOOK_RESULT_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONTRACT_HOOK_RESULT_DIR/../core/errors.sh"

# Create a new HookResult
# Usage: hook_result_new result 1  # success
#        hook_result_new result 0  # failure
hook_result_new() {
    local -n __hr_result=$1
    local success="$2"

    __hr_result=(
        [success]="$success"
        [error_code]=""
        [error_message]=""
        [files_modified]=""
    )
}

# Create a new failed HookResult with error details
# Usage: hook_result_new_failure result $E_PERMISSION "Cannot write to target"
hook_result_new_failure() {
    local -n __hr_result=$1
    local error_code="$2"
    local error_message="$3"

    __hr_result=(
        [success]=0
        [error_code]="$error_code"
        [error_message]="$error_message"
        [files_modified]=""
    )
}

# Validate a HookResult
# Returns: E_OK if valid, E_VALIDATION if not (with errors to stderr)
hook_result_validate() {
    local -n __hr_result=$1
    local errors=()

    # success is required
    if [[ -z "${__hr_result[success]+set}" ]]; then
        errors+=("success is required")
    else
        # success must be 0 or 1
        local success="${__hr_result[success]}"
        if [[ "$success" != "0" && "$success" != "1" ]]; then
            errors+=("success must be 0 or 1, got: $success")
        fi

        # If failure (success=0), error_code should be set
        if [[ "$success" == "0" && -z "${__hr_result[error_code]:-}" ]]; then
            errors+=("error_code is required when success=0")
        fi
    fi

    # Validate error_code is numeric if present
    local error_code="${__hr_result[error_code]:-}"
    if [[ -n "$error_code" && ! "$error_code" =~ ^[0-9]+$ ]]; then
        errors+=("error_code must be numeric: $error_code")
    fi

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'HookResult validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Set error details (implies failure)
hook_result_set_error() {
    local -n __hr_result=$1
    local code="$2"
    local message="$3"

    __hr_result[success]=0
    __hr_result[error_code]="$code"
    __hr_result[error_message]="$message"
}

# Add a modified file path
# Usage: hook_result_add_file result "/path/to/file"
hook_result_add_file() {
    local -n __hr_result=$1
    local path="$2"

    if [[ -z "${__hr_result[files_modified]:-}" ]]; then
        __hr_result[files_modified]="$path"
    else
        __hr_result[files_modified]+=" $path"
    fi
}

# Check if result is success
# Returns: 0 if success, 1 if failure
hook_result_is_success() {
    local -n __hr_result=$1
    [[ "${__hr_result[success]:-0}" == "1" ]]
}

# Getters
hook_result_get_error_code() {
    local -n __hr_result=$1
    printf '%s' "${__hr_result[error_code]:-}"
}

hook_result_get_error_message() {
    local -n __hr_result=$1
    printf '%s' "${__hr_result[error_message]:-}"
}

hook_result_get_files_modified() {
    local -n __hr_result=$1
    printf '%s' "${__hr_result[files_modified]:-}"
}
