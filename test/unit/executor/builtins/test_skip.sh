#!/usr/bin/env bash
# test/unit/executor/builtins/test_skip.sh
# Unit tests for executor/builtins/skip.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../test_utils.sh"

# Source dependencies
source "$SCRIPT_DIR/../../../../lib/core/errors.sh"
source "$SCRIPT_DIR/../../../../lib/contracts/hook_result.sh"

# Module under test
source "$SCRIPT_DIR/../../../../lib/executor/builtins/skip.sh"

echo "Testing: executor/builtins/skip"
echo ""

# Test 1: skip returns success
test_skip_returns_success() {
    declare -A config
    declare -A result

    local rc=0
    builtin_skip config result || rc=$?

    assert_equals "$E_OK" "$rc" "Should return E_OK"
}

# Test 2: skip sets result to success
test_skip_sets_success_result() {
    declare -A config
    declare -A result

    builtin_skip config result

    local success
    success=$(hook_result_is_success result && echo "1" || echo "0")
    assert_equals "1" "$success" "Result should indicate success"
}

# Run tests
test_skip_returns_success
test_skip_sets_success_result

print_summary
