#!/usr/bin/env bash
# test/unit/executor/test_builtin_registry.sh
# Tests that all expected builtins are registered

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source the runner which registers all builtins
source "$SCRIPT_DIR/../../../lib/core/errors.sh"
source "$SCRIPT_DIR/../../../lib/executor/runner.sh"

echo "Testing: Builtin Registry Completeness"
echo ""

# Initialize runner to register strategies
runner_init "/tmp/test-dotfiles"

# Test: All documented builtins should be registered
test_all_builtins_registered() {
    # These are all the builtin strategies that should be available
    local expected_builtins=(
        "symlink"
        "concat"
        "source"
        "json-merge"
        "json"
        "skip"
    )

    for builtin in "${expected_builtins[@]}"; do
        assert_success "strategy_exists '$builtin'" "builtin:$builtin should be registered"
    done
}

# Test: Skip builtin should be available for install_hook
test_skip_available_for_install_hook() {
    # This specifically tests the use case that caused the original bug:
    # install_hook: "builtin:skip" should work
    assert_success "strategy_exists 'skip'" "skip strategy should exist for install_hook usage"
}

# Run tests
test_all_builtins_registered
test_skip_available_for_install_hook

print_summary
