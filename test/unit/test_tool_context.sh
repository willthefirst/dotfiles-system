#!/usr/bin/env bash
# test/unit/test_tool_context.sh
# Unit tests for TOOL_CTX context pattern

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"
source "$SCRIPT_DIR/../../lib/layers.sh"

echo "Testing: TOOL_CTX context pattern"
echo ""

# Setup test environment
setup_test_env

# Create a mock tool.conf for testing
setup_mock_tool_conf() {
    mkdir -p "$TEST_TEMP_DIR/tools/mock"
    cat > "$TEST_TEMP_DIR/tools/mock/tool.conf" << 'EOF'
target="${HOME}/.config/mock"
install_hook="builtin:skip"
merge_hook="builtin:symlink"
layers_base="local:configs/mock"
layers_work="WORK_REPO:mock"
env_MOCK_VAR="test_value"
env_ANOTHER_VAR="another_value"
EOF
}

setup_mock_tool_conf

# Test 1: init_tool_ctx clears context
test_init_clears_context() {
    # Set some values
    TOOL_CTX[target]="old_value"
    TOOL_CTX[custom_key]="custom"

    # Initialize
    init_tool_ctx

    local target
    target=$(ctx_get "target")
    assert_equals "" "$target" "init_tool_ctx should clear target"
}

# Test 2: parse_tool_conf populates context
test_parse_populates_context() {
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    local target
    target=$(ctx_get "target")
    assert_equals "$HOME/.config/mock" "$target" "Should parse target"

    local install_hook
    install_hook=$(ctx_get "install_hook")
    assert_equals "builtin:skip" "$install_hook" "Should parse install_hook"

    local merge_hook
    merge_hook=$(ctx_get "merge_hook")
    assert_equals "builtin:symlink" "$merge_hook" "Should parse merge_hook"
}

# Test 3: ctx_get_layer retrieves layer specs
test_get_layer() {
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    local base_layer
    base_layer=$(ctx_get_layer "base")
    assert_equals "local:configs/mock" "$base_layer" "Should get base layer"

    local work_layer
    work_layer=$(ctx_get_layer "work")
    assert_equals "WORK_REPO:mock" "$work_layer" "Should get work layer"
}

# Test 4: ctx_get_env retrieves env vars
test_get_env() {
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    local mock_var
    mock_var=$(ctx_get_env "MOCK_VAR")
    assert_equals "test_value" "$mock_var" "Should get MOCK_VAR"

    local another_var
    another_var=$(ctx_get_env "ANOTHER_VAR")
    assert_equals "another_value" "$another_var" "Should get ANOTHER_VAR"
}

# Test 5: ctx_env_keys returns all env keys
test_env_keys() {
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    local keys
    keys=$(ctx_env_keys)

    # Should contain both keys (order may vary)
    assert_contains "$keys" "MOCK_VAR" "Should include MOCK_VAR in keys"
    assert_contains "$keys" "ANOTHER_VAR" "Should include ANOTHER_VAR in keys"
}

# Test 6: Context is isolated between parses
test_context_isolation() {
    # Parse first config
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    local first_target
    first_target=$(ctx_get "target")

    # Create a different config
    cat > "$TEST_TEMP_DIR/tools/mock/tool2.conf" << 'EOF'
target="/different/path"
merge_hook="builtin:concat"
layers_base="local:other"
EOF

    # Parse second config
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool2.conf"

    local second_target
    second_target=$(ctx_get "target")
    assert_equals "/different/path" "$second_target" "Should have new target"

    # Old env vars should be gone
    local old_var
    old_var=$(ctx_get_env "MOCK_VAR")
    assert_equals "" "$old_var" "Old env vars should be cleared"
}

# Test 7: Legacy globals are synced
test_legacy_sync() {
    parse_tool_conf "$TEST_TEMP_DIR/tools/mock/tool.conf"

    # Check legacy globals are populated
    assert_equals "$HOME/.config/mock" "$TOOL_TARGET" "TOOL_TARGET should be synced"
    assert_equals "builtin:skip" "$TOOL_INSTALL_HOOK" "TOOL_INSTALL_HOOK should be synced"
    assert_equals "builtin:symlink" "$TOOL_MERGE_HOOK" "TOOL_MERGE_HOOK should be synced"
}

# Run all tests
test_init_clears_context
test_parse_populates_context
test_get_layer
test_get_env
test_env_keys
test_context_isolation
test_legacy_sync

# Cleanup
teardown_test_env

print_summary
