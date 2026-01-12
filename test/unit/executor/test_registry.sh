#!/usr/bin/env bash
# test/unit/executor/test_registry.sh
# Unit tests for executor/registry.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/executor/registry.sh"

echo "Testing: executor/registry"
echo ""

# Setup: Clear registry before each test
setup() {
    strategy_clear
}

# Test 1: strategy_register adds a strategy
test_strategy_register() {
    setup
    local rc=0
    strategy_register "test" "my_handler" || rc=$?

    assert_equals 0 "$rc" "strategy_register should return 0 on success"
}

# Test 2: strategy_register requires name
test_strategy_register_requires_name() {
    setup
    local rc=0
    strategy_register "" "handler" 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "strategy_register should fail without name"
}

# Test 3: strategy_register requires handler
test_strategy_register_requires_handler() {
    setup
    local rc=0
    strategy_register "test" "" 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "strategy_register should fail without handler"
}

# Test 4: strategy_exists returns true for registered
test_strategy_exists_registered() {
    setup
    strategy_register "test" "my_handler"

    if strategy_exists "test"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: strategy_exists returns true for registered"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: strategy_exists should return true for registered"
    fi
}

# Test 5: strategy_exists returns false for unregistered
test_strategy_exists_unregistered() {
    setup

    if ! strategy_exists "nonexistent"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: strategy_exists returns false for unregistered"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: strategy_exists should return false for unregistered"
    fi
}

# Test 6: strategy_get returns handler
test_strategy_get() {
    setup
    strategy_register "test" "my_handler_func"

    local handler
    handler=$(strategy_get "test")
    assert_equals "my_handler_func" "$handler" "strategy_get should return handler"
}

# Test 7: strategy_get fails for unknown strategy
test_strategy_get_unknown() {
    setup
    local rc=0
    strategy_get "unknown" 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "strategy_get should fail for unknown"
}

# Test 8: strategy_list lists all strategies
test_strategy_list() {
    setup
    strategy_register "alpha" "handler_a"
    strategy_register "beta" "handler_b"

    local list
    list=$(strategy_list)

    assert_contains "$list" "alpha" "List should contain alpha"
    assert_contains "$list" "beta" "List should contain beta"
}

# Test 9: strategy_unregister removes strategy
test_strategy_unregister() {
    setup
    strategy_register "test" "handler"
    strategy_unregister "test"

    if ! strategy_exists "test"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: strategy_unregister removes strategy"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: strategy_unregister should remove strategy"
    fi
}

# Test 10: strategy_unregister fails for unknown
test_strategy_unregister_unknown() {
    setup
    local rc=0
    strategy_unregister "unknown" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "strategy_unregister should fail for unknown"
}

# Test 11: strategy_clear removes all strategies
test_strategy_clear() {
    setup
    strategy_register "one" "h1"
    strategy_register "two" "h2"
    strategy_clear

    local count
    count=$(strategy_count)
    assert_equals 0 "$count" "strategy_clear should remove all strategies"
}

# Test 12: strategy_count returns correct count
test_strategy_count() {
    setup
    strategy_register "a" "h1"
    strategy_register "b" "h2"
    strategy_register "c" "h3"

    local count
    count=$(strategy_count)
    assert_equals 3 "$count" "strategy_count should return 3"
}

# Test 13: strategy_register can override existing
test_strategy_register_override() {
    setup
    strategy_register "test" "old_handler"
    strategy_register "test" "new_handler"

    local handler
    handler=$(strategy_get "test")
    assert_equals "new_handler" "$handler" "strategy_register should allow override"
}

# Test 14: strategy_list is empty after clear
test_strategy_list_empty() {
    setup

    local list
    list=$(strategy_list)
    assert_equals "" "$list" "strategy_list should be empty after clear"
}

# Run all tests
test_strategy_register
test_strategy_register_requires_name
test_strategy_register_requires_handler
test_strategy_exists_registered
test_strategy_exists_unregistered
test_strategy_get
test_strategy_get_unknown
test_strategy_list
test_strategy_unregister
test_strategy_unregister_unknown
test_strategy_clear
test_strategy_count
test_strategy_register_override
test_strategy_list_empty

print_summary
