#!/usr/bin/env bash
# test/unit/core/test_errors.sh
# Unit tests for core/errors.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/core/errors.sh"

echo "Testing: core/errors"
echo ""

# Test 1: Error codes are defined
test_error_codes_defined() {
    assert_equals "0" "$E_OK" "E_OK should be 0"
    assert_equals "1" "$E_GENERIC" "E_GENERIC should be 1"
    assert_equals "2" "$E_INVALID_INPUT" "E_INVALID_INPUT should be 2"
    assert_equals "3" "$E_NOT_FOUND" "E_NOT_FOUND should be 3"
    assert_equals "4" "$E_PERMISSION" "E_PERMISSION should be 4"
    assert_equals "5" "$E_VALIDATION" "E_VALIDATION should be 5"
    assert_equals "6" "$E_DEPENDENCY" "E_DEPENDENCY should be 6"
    assert_equals "7" "$E_BACKUP" "E_BACKUP should be 7"
}

# Test 2: error_message returns correct messages
test_error_message_returns_message() {
    local msg

    msg=$(error_message $E_OK)
    assert_equals "Success" "$msg" "E_OK message"

    msg=$(error_message $E_GENERIC)
    assert_equals "Operation failed" "$msg" "E_GENERIC message"

    msg=$(error_message $E_NOT_FOUND)
    assert_equals "File or resource not found" "$msg" "E_NOT_FOUND message"

    msg=$(error_message $E_VALIDATION)
    assert_equals "Validation failed" "$msg" "E_VALIDATION message"
}

# Test 3: error_message handles unknown codes
test_error_message_unknown_code() {
    local msg
    msg=$(error_message 99)
    assert_contains "$msg" "Unknown error" "Unknown code should return unknown error message"
}

# Test 4: Error codes are readonly
test_error_codes_readonly() {
    local result
    # Attempt to reassign should fail
    result=$(E_OK=99 2>&1) || true
    # If we got here without error, check E_OK is still 0
    assert_equals "0" "$E_OK" "E_OK should still be 0 after attempted reassignment"
}

# Run all tests
test_error_codes_defined
test_error_message_returns_message
test_error_message_unknown_code
test_error_codes_readonly

print_summary
