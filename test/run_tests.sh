#!/usr/bin/env bash
# test/run_tests.sh
# Test runner for dotfiles-system framework

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../lib"

# Source test utilities
source "$SCRIPT_DIR/test_utils.sh"

# Colors
BLUE='\033[0;34m'
NC='\033[0m'

echo "============================================"
echo "Dotfiles System Test Suite"
echo "============================================"
echo ""

TOTAL_PASSED=0
TOTAL_FAILED=0
TOTAL_RUN=0

# Run a single test file
run_test_file() {
    local test_file="$1"
    local test_name
    test_name=$(basename "$test_file" .sh)

    echo -e "${BLUE}Running: $test_name${NC}"
    echo "--------------------------------------------"

    reset_counters

    # Run the test file in a subshell to isolate it
    if bash "$test_file"; then
        :
    fi

    # Get results from the subshell (we need to source it to get counters)
    source "$test_file" 2>/dev/null || true

    TOTAL_RUN=$((TOTAL_RUN + TESTS_RUN))
    TOTAL_PASSED=$((TOTAL_PASSED + TESTS_PASSED))
    TOTAL_FAILED=$((TOTAL_FAILED + TESTS_FAILED))

    echo ""
}

# Find and run all unit tests
echo "Unit Tests"
echo "============================================"
for test_file in "$SCRIPT_DIR"/unit/test_*.sh; do
    if [[ -f "$test_file" ]]; then
        run_test_file "$test_file"
    fi
done

# Run integration tests if requested
if [[ "${1:-}" == "--integration" ]]; then
    echo ""
    echo "Integration Tests"
    echo "============================================"
    for test_file in "$SCRIPT_DIR"/integration/test_*.sh; do
        if [[ -f "$test_file" ]]; then
            run_test_file "$test_file"
        fi
    done
fi

# Final summary
echo ""
echo "============================================"
echo "Final Results"
echo "============================================"
echo "Total Tests Run: $TOTAL_RUN"
echo -e "Passed: ${GREEN}$TOTAL_PASSED${NC}"
echo -e "Failed: ${RED}$TOTAL_FAILED${NC}"
echo "============================================"

# Exit with failure if any tests failed
if [[ $TOTAL_FAILED -gt 0 ]]; then
    exit 1
fi

exit 0
