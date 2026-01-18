#!/usr/bin/env bash
# test/run_tests.sh
# Test runner for dotfiles-system framework

# Re-exec with homebrew bash if current bash is too old (macOS ships with 3.2)
# Required for associative arrays and declare -g
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    if [[ -x /opt/homebrew/bin/bash ]]; then
        exec /opt/homebrew/bin/bash "$0" "$@"
    elif [[ -x /usr/local/bin/bash ]]; then
        exec /usr/local/bin/bash "$0" "$@"
    else
        echo "Error: Bash 4+ required (found ${BASH_VERSION})" >&2
        echo "On macOS, install via: brew install bash" >&2
        exit 1
    fi
fi

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

    # Run test and capture output
    # Use $BASH to preserve bash 4+ interpreter after re-exec
    local output
    output=$("$BASH" "$test_file" 2>&1) || true
    echo "$output"

    # Count PASS/FAIL lines directly (more robust than parsing summary)
    local passed failed
    passed=$(echo "$output" | grep -c 'PASS' || true)
    failed=$(echo "$output" | grep -c 'FAIL' || true)

    TOTAL_RUN=$((TOTAL_RUN + passed + failed))
    TOTAL_PASSED=$((TOTAL_PASSED + passed))
    TOTAL_FAILED=$((TOTAL_FAILED + failed))

    echo ""
}

# Find and run all unit tests (including subdirectories)
echo "Unit Tests"
echo "============================================"

# First run tests in unit/ directly
for test_file in "$SCRIPT_DIR"/unit/test_*.sh; do
    if [[ -f "$test_file" ]]; then
        run_test_file "$test_file"
    fi
done

# Then run tests in unit subdirectories (e.g., unit/core/)
for subdir in "$SCRIPT_DIR"/unit/*/; do
    if [[ -d "$subdir" ]]; then
        for test_file in "$subdir"test_*.sh; do
            if [[ -f "$test_file" ]]; then
                run_test_file "$test_file"
            fi
        done
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
