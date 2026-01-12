#!/usr/bin/env bash
# test/unit/core/test_log.sh
# Unit tests for core/log.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/core/log.sh"

echo "Testing: core/log"
echo ""

# Setup: Initialize mock mode before each test
setup() {
    declare -gA log_cfg=([output]="mock" [level]="debug")
    log_init log_cfg
    log_mock_reset
}

# Test 1: log_section captures message
test_log_section_captures() {
    setup
    log_section "Test Section"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[info] Test Section" "log_section should capture message"
}

# Test 2: log_step captures message
test_log_step_captures() {
    setup
    log_step "Test Step"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[info] Test Step" "log_step should capture message"
}

# Test 3: log_ok captures message
test_log_ok_captures() {
    setup
    log_ok "Operation succeeded"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[info] Operation succeeded" "log_ok should capture message"
}

# Test 4: log_warn captures message
test_log_warn_captures() {
    setup
    log_warn "Warning message"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[warn] Warning message" "log_warn should capture message"
}

# Test 5: log_error captures message
test_log_error_captures() {
    setup
    log_error "Error occurred"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[error] Error occurred" "log_error should capture message"
}

# Test 6: log_detail only logs in debug mode
test_log_detail_debug_mode() {
    setup
    log_detail "Debug info"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[debug] Debug info" "log_detail should capture in debug mode"
}

# Test 7: log_detail filtered in info mode
test_log_detail_info_mode() {
    declare -gA log_cfg=([output]="mock" [level]="info")
    log_init log_cfg
    log_mock_reset

    log_detail "Debug info"

    local count
    count=$(log_mock_count)
    assert_equals "0" "$count" "log_detail should not log in info mode"
}

# Test 8: log_mock_reset clears buffer
test_log_mock_reset() {
    setup
    log_ok "Message 1"
    log_ok "Message 2"

    local before
    before=$(log_mock_count)
    assert_equals "2" "$before" "Should have 2 messages before reset"

    log_mock_reset

    local after
    after=$(log_mock_count)
    assert_equals "0" "$after" "Should have 0 messages after reset"
}

# Test 9: log_mock_assert finds pattern
test_log_mock_assert_finds() {
    setup
    log_error "Connection failed"

    if log_mock_assert "Connection"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: log_mock_assert finds pattern"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: log_mock_assert should find pattern"
    fi
}

# Test 10: log_mock_assert fails for missing pattern
test_log_mock_assert_fails() {
    setup
    log_ok "Success"

    if ! log_mock_assert "nonexistent"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: log_mock_assert correctly fails for missing pattern"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: log_mock_assert should fail for missing pattern"
    fi
}

# Test 11: log_skip captures message
test_log_skip_captures() {
    setup
    log_skip "Skipped operation"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "[info] Skipped operation" "log_skip should capture message"
}

# Test 12: Error level filters info messages
test_error_level_filters_info() {
    declare -gA log_cfg=([output]="mock" [level]="error")
    log_init log_cfg
    log_mock_reset

    log_ok "Info message"
    log_warn "Warning message"
    log_error "Error message"

    local count
    count=$(log_mock_count)
    assert_equals "1" "$count" "Only error should be logged at error level"

    local logs
    logs=$(log_mock_get)
    assert_contains "$logs" "Error message" "Error message should be logged"
}

# Run all tests
test_log_section_captures
test_log_step_captures
test_log_ok_captures
test_log_warn_captures
test_log_error_captures
test_log_detail_debug_mode
test_log_detail_info_mode
test_log_mock_reset
test_log_mock_assert_finds
test_log_mock_assert_fails
test_log_skip_captures
test_error_level_filters_info

print_summary
