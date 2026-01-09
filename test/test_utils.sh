#!/usr/bin/env bash
# test/test_utils.sh
# Test assertion and helper utilities

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# Assertion Functions
# ============================================================================

# Assert that two values are equal
# Usage: assert_equals "expected" "actual" "message"
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Expected: '$expected'"
        echo "  Actual:   '$actual'"
        return 1
    fi
}

# Assert that two values are not equal
# Usage: assert_not_equals "not_expected" "actual" "message"
assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    ((TESTS_RUN++))

    if [[ "$not_expected" != "$actual" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Should not be: '$not_expected'"
        echo "  Actual:        '$actual'"
        return 1
    fi
}

# Assert that a string contains a substring
# Usage: assert_contains "haystack" "needle" "message"
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Looking for: '$needle'"
        echo "  In:          '$haystack'"
        return 1
    fi
}

# Assert that a file exists
# Usage: assert_file_exists "/path/to/file" "message"
assert_file_exists() {
    local path="$1"
    local message="${2:-File should exist: $path}"

    ((TESTS_RUN++))

    if [[ -f "$path" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  File not found: '$path'"
        return 1
    fi
}

# Assert that a directory exists
# Usage: assert_dir_exists "/path/to/dir" "message"
assert_dir_exists() {
    local path="$1"
    local message="${2:-Directory should exist: $path}"

    ((TESTS_RUN++))

    if [[ -d "$path" ]]; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Directory not found: '$path'"
        return 1
    fi
}

# Assert that a command exits with code 0
# Usage: assert_success "command" "message"
assert_success() {
    local cmd="$1"
    local message="${2:-Command should succeed}"

    ((TESTS_RUN++))

    if eval "$cmd" &>/dev/null; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Command failed: $cmd"
        return 1
    fi
}

# Assert that a command exits with non-zero code
# Usage: assert_failure "command" "message"
assert_failure() {
    local cmd="$1"
    local message="${2:-Command should fail}"

    ((TESTS_RUN++))

    if ! eval "$cmd" &>/dev/null; then
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: $message"
        echo "  Command succeeded but should have failed: $cmd"
        return 1
    fi
}

# ============================================================================
# Setup/Teardown Helpers
# ============================================================================

# Create a temporary test directory
# Usage: setup_test_env
# Sets: TEST_TEMP_DIR
setup_test_env() {
    TEST_TEMP_DIR=$(mktemp -d)
    export TEST_TEMP_DIR
    export DOTFILES_BACKUP_DIR="$TEST_TEMP_DIR/backup"
}

# Clean up temporary test directory
# Usage: teardown_test_env
teardown_test_env() {
    if [[ -n "${TEST_TEMP_DIR:-}" && -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
    unset TEST_TEMP_DIR DOTFILES_BACKUP_DIR
}

# ============================================================================
# Test Reporting
# ============================================================================

# Print test summary
# Usage: print_summary
print_summary() {
    echo ""
    echo "============================================"
    echo "Test Summary"
    echo "============================================"
    echo "Total:  $TESTS_RUN"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "============================================"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Reset test counters
# Usage: reset_counters
reset_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
}
