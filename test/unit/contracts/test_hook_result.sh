#!/usr/bin/env bash
# test/unit/contracts/test_hook_result.sh
# Unit tests for contracts/hook_result.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/contracts/hook_result.sh"

echo "Testing: contracts/hook_result"
echo ""

# ============================================================================
# Constructor Tests
# ============================================================================

test_hook_result_new_success() {
    declare -A result
    hook_result_new result 1

    assert_equals "1" "${result[success]}" "success should be 1"
    assert_equals "" "${result[error_code]}" "error_code should be empty"
    assert_equals "" "${result[error_message]}" "error_message should be empty"
    assert_equals "" "${result[files_modified]}" "files_modified should be empty"
}

test_hook_result_new_failure() {
    declare -A result
    hook_result_new result 0

    assert_equals "0" "${result[success]}" "success should be 0"
}

test_hook_result_new_failure_with_details() {
    declare -A result
    hook_result_new_failure result "$E_PERMISSION" "Cannot write to /etc/hosts"

    assert_equals "0" "${result[success]}" "success should be 0"
    assert_equals "$E_PERMISSION" "${result[error_code]}" "error_code should be set"
    assert_equals "Cannot write to /etc/hosts" "${result[error_message]}" "error_message should be set"
}

# ============================================================================
# Validation Tests - Valid Cases
# ============================================================================

test_hook_result_validate_valid_success() {
    declare -A result
    hook_result_new result 1

    hook_result_validate result
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid success result should pass"
}

test_hook_result_validate_valid_failure() {
    declare -A result
    hook_result_new_failure result "$E_NOT_FOUND" "File not found"

    hook_result_validate result
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid failure result should pass"
}

test_hook_result_validate_success_with_files() {
    declare -A result
    hook_result_new result 1
    hook_result_add_file result "/home/user/.gitconfig"

    hook_result_validate result
    local rc=$?

    assert_equals "$E_OK" "$rc" "success result with files should pass"
}

# ============================================================================
# Validation Tests - Invalid Cases
# ============================================================================

test_hook_result_validate_invalid_success_value() {
    declare -A result
    result=(
        [success]="yes"
        [error_code]=""
        [error_message]=""
        [files_modified]=""
    )

    hook_result_validate result 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "success must be 0 or 1"
}

test_hook_result_validate_failure_without_error_code() {
    declare -A result
    hook_result_new result 0
    # Not setting error_code

    hook_result_validate result 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "failure without error_code should fail"
}

test_hook_result_validate_non_numeric_error_code() {
    declare -A result
    result=(
        [success]="0"
        [error_code]="error"
        [error_message]="Something failed"
        [files_modified]=""
    )

    hook_result_validate result 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "non-numeric error_code should fail"
}

test_hook_result_validate_missing_success() {
    declare -A result
    result=(
        [error_code]=""
        [error_message]=""
        [files_modified]=""
    )

    hook_result_validate result 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing success should fail"
}

# ============================================================================
# Error Management Tests
# ============================================================================

test_hook_result_set_error() {
    declare -A result
    hook_result_new result 1

    hook_result_set_error result "$E_BACKUP" "Backup failed"

    assert_equals "0" "${result[success]}" "success should be set to 0"
    assert_equals "$E_BACKUP" "${result[error_code]}" "error_code should be set"
    assert_equals "Backup failed" "${result[error_message]}" "error_message should be set"
}

test_hook_result_set_error_overwrites() {
    declare -A result
    hook_result_new_failure result "$E_NOT_FOUND" "Not found"

    hook_result_set_error result "$E_PERMISSION" "Permission denied"

    assert_equals "$E_PERMISSION" "${result[error_code]}" "error_code should be overwritten"
    assert_equals "Permission denied" "${result[error_message]}" "error_message should be overwritten"
}

# ============================================================================
# File Tracking Tests
# ============================================================================

test_hook_result_add_file() {
    declare -A result
    hook_result_new result 1

    hook_result_add_file result "/home/user/.gitconfig"

    assert_equals "/home/user/.gitconfig" "${result[files_modified]}" "file should be added"
}

test_hook_result_add_multiple_files() {
    declare -A result
    hook_result_new result 1

    hook_result_add_file result "/home/user/.gitconfig"
    hook_result_add_file result "/home/user/.zshrc"
    hook_result_add_file result "/home/user/.vimrc"

    assert_equals "/home/user/.gitconfig /home/user/.zshrc /home/user/.vimrc" \
        "${result[files_modified]}" "files should be space-separated"
}

# ============================================================================
# is_success Tests
# ============================================================================

test_hook_result_is_success_true() {
    declare -A result
    hook_result_new result 1

    hook_result_is_success result
    local rc=$?

    assert_equals "0" "$rc" "is_success should return 0 for success=1"
}

test_hook_result_is_success_false() {
    declare -A result
    hook_result_new_failure result "$E_GENERIC" "Failed"

    hook_result_is_success result
    local rc=$?

    assert_equals "1" "$rc" "is_success should return 1 for success=0"
}

# ============================================================================
# Getter Tests
# ============================================================================

test_hook_result_get_error_code() {
    declare -A result
    hook_result_new_failure result "$E_NOT_FOUND" "File not found"

    local code
    code=$(hook_result_get_error_code result)

    assert_equals "$E_NOT_FOUND" "$code" "get_error_code should return error code"
}

test_hook_result_get_error_message() {
    declare -A result
    hook_result_new_failure result "$E_NOT_FOUND" "File not found: config.sh"

    local msg
    msg=$(hook_result_get_error_message result)

    assert_equals "File not found: config.sh" "$msg" "get_error_message should return message"
}

test_hook_result_get_files_modified() {
    declare -A result
    hook_result_new result 1
    hook_result_add_file result "/path/one"
    hook_result_add_file result "/path/two"

    local files
    files=$(hook_result_get_files_modified result)

    assert_equals "/path/one /path/two" "$files" "get_files_modified should return files"
}

test_hook_result_get_empty_values() {
    declare -A result
    hook_result_new result 1

    local code msg files
    code=$(hook_result_get_error_code result)
    msg=$(hook_result_get_error_message result)
    files=$(hook_result_get_files_modified result)

    assert_equals "" "$code" "get_error_code should return empty"
    assert_equals "" "$msg" "get_error_message should return empty"
    assert_equals "" "$files" "get_files_modified should return empty"
}

# ============================================================================
# Error Message Tests
# ============================================================================

test_hook_result_validate_outputs_errors_to_stderr() {
    declare -A result
    result=(
        [success]="invalid"
        [error_code]=""
        [error_message]=""
        [files_modified]=""
    )

    local stderr_output
    stderr_output=$(hook_result_validate result 2>&1 >/dev/null) || true

    assert_contains "$stderr_output" "validation failed" "should output failure message"
    assert_contains "$stderr_output" "success must be 0 or 1" "should describe error"
}

# ============================================================================
# Run Tests
# ============================================================================

test_hook_result_new_success
test_hook_result_new_failure
test_hook_result_new_failure_with_details

test_hook_result_validate_valid_success
test_hook_result_validate_valid_failure
test_hook_result_validate_success_with_files

test_hook_result_validate_invalid_success_value
test_hook_result_validate_failure_without_error_code
test_hook_result_validate_non_numeric_error_code
test_hook_result_validate_missing_success

test_hook_result_set_error
test_hook_result_set_error_overwrites

test_hook_result_add_file
test_hook_result_add_multiple_files

test_hook_result_is_success_true
test_hook_result_is_success_false

test_hook_result_get_error_code
test_hook_result_get_error_message
test_hook_result_get_files_modified
test_hook_result_get_empty_values

test_hook_result_validate_outputs_errors_to_stderr

print_summary
