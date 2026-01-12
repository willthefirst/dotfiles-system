#!/usr/bin/env bash
# test/unit/contracts/test_tool_config.sh
# Unit tests for contracts/tool_config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/contracts/tool_config.sh"

echo "Testing: contracts/tool_config"
echo ""

# ============================================================================
# Constructor Tests
# ============================================================================

test_tool_config_new_creates_config() {
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" "builtin:symlink"

    assert_equals "git" "${config[tool_name]}" "tool_name should be set"
    assert_equals "/home/user/.gitconfig" "${config[target]}" "target should be set"
    assert_equals "builtin:symlink" "${config[merge_hook]}" "merge_hook should be set"
    assert_equals "" "${config[install_hook]}" "install_hook should be empty initially"
    assert_equals "0" "${config[layer_count]}" "layer_count should be 0 initially"
}

test_tool_config_new_with_tilde_target() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"

    assert_equals "~/.gitconfig" "${config[target]}" "target with tilde should be accepted"
}

# ============================================================================
# Validation Tests - Valid Cases
# ============================================================================

test_tool_config_validate_valid_builtin() {
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" "builtin:symlink"

    tool_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid config with builtin hook should pass"
}

test_tool_config_validate_valid_script_hook() {
    declare -A config
    tool_config_new config "nvim" "~/.config/nvim" "./tools/nvim/merge.sh"

    tool_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid config with script hook should pass"
}

test_tool_config_validate_valid_with_install_hook() {
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" "builtin:symlink"
    tool_config_set_install_hook config "builtin:none"

    tool_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "config with install hook should pass"
}

test_tool_config_validate_valid_with_layers() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_add_layer config "work" "STRIPE_DOTFILES" "stripe/git"

    tool_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "config with valid layers should pass"
}

test_tool_config_validate_tool_name_with_hyphen() {
    declare -A config
    tool_config_new config "vs-code" "/home/user/.config/Code" "builtin:copy"

    tool_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "tool name with hyphen should be valid"
}

# ============================================================================
# Validation Tests - Invalid Cases
# ============================================================================

test_tool_config_validate_missing_tool_name() {
    declare -A config
    tool_config_new config "" "/home/user/.gitconfig" "builtin:symlink"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing tool_name should fail"
}

test_tool_config_validate_missing_target() {
    declare -A config
    tool_config_new config "git" "" "builtin:symlink"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing target should fail"
}

test_tool_config_validate_missing_merge_hook() {
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" ""

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing merge_hook should fail"
}

test_tool_config_validate_relative_target() {
    declare -A config
    tool_config_new config "git" "relative/path" "builtin:symlink"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "relative target should fail"
}

test_tool_config_validate_hook_with_spaces() {
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" "path with spaces"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "merge_hook with spaces should fail"
}

test_tool_config_validate_invalid_layer_source() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "invalid_source" "configs/git"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "layer with invalid source should fail"
}

test_tool_config_validate_layer_absolute_path() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "/absolute/path"

    tool_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "layer with absolute path should fail"
}

# ============================================================================
# Layer Management Tests
# ============================================================================

test_tool_config_add_layer() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"

    tool_config_add_layer config "base" "local" "configs/git"

    assert_equals "1" "${config[layer_count]}" "layer_count should be 1"
    assert_equals "base" "${config[layer_0_name]}" "layer name should be stored"
    assert_equals "local" "${config[layer_0_source]}" "layer source should be stored"
    assert_equals "configs/git" "${config[layer_0_path]}" "layer path should be stored"
}

test_tool_config_add_multiple_layers() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"

    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_add_layer config "work" "STRIPE_DOTFILES" "stripe/git"
    tool_config_add_layer config "personal" "local" "personal/git"

    assert_equals "3" "${config[layer_count]}" "layer_count should be 3"
    assert_equals "base" "${config[layer_0_name]}" "first layer name"
    assert_equals "work" "${config[layer_1_name]}" "second layer name"
    assert_equals "personal" "${config[layer_2_name]}" "third layer name"
}

test_tool_config_set_layer_resolved() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    tool_config_set_layer_resolved config 0 "/home/user/.dotfiles/configs/git"

    assert_equals "/home/user/.dotfiles/configs/git" "${config[layer_0_resolved]}" \
        "resolved path should be set"
}

# ============================================================================
# Getter Tests
# ============================================================================

test_tool_config_getters() {
    declare -A config
    tool_config_new config "nvim" "~/.config/nvim" "builtin:copy"
    tool_config_set_install_hook config "./tools/nvim/install.sh"
    tool_config_add_layer config "base" "local" "configs/nvim"

    assert_equals "nvim" "$(tool_config_get_tool_name config)" "get_tool_name"
    assert_equals "~/.config/nvim" "$(tool_config_get_target config)" "get_target"
    assert_equals "builtin:copy" "$(tool_config_get_merge_hook config)" "get_merge_hook"
    assert_equals "./tools/nvim/install.sh" "$(tool_config_get_install_hook config)" "get_install_hook"
    assert_equals "1" "$(tool_config_get_layer_count config)" "get_layer_count"
}

test_tool_config_layer_getters() {
    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/resolved/path"

    assert_equals "base" "$(tool_config_get_layer_name config 0)" "get_layer_name"
    assert_equals "local" "$(tool_config_get_layer_source config 0)" "get_layer_source"
    assert_equals "configs/git" "$(tool_config_get_layer_path config 0)" "get_layer_path"
    assert_equals "/resolved/path" "$(tool_config_get_layer_resolved config 0)" "get_layer_resolved"
}

# ============================================================================
# Error Message Tests
# ============================================================================

test_tool_config_validate_outputs_errors_to_stderr() {
    declare -A config
    tool_config_new config "" "" ""

    local stderr_output
    stderr_output=$(tool_config_validate config 2>&1 >/dev/null) || true

    assert_contains "$stderr_output" "validation failed" "should output failure message"
    assert_contains "$stderr_output" "tool_name is required" "should list tool_name error"
    assert_contains "$stderr_output" "target is required" "should list target error"
    assert_contains "$stderr_output" "merge_hook is required" "should list merge_hook error"
}

# ============================================================================
# Run Tests
# ============================================================================

test_tool_config_new_creates_config
test_tool_config_new_with_tilde_target

test_tool_config_validate_valid_builtin
test_tool_config_validate_valid_script_hook
test_tool_config_validate_valid_with_install_hook
test_tool_config_validate_valid_with_layers
test_tool_config_validate_tool_name_with_hyphen

test_tool_config_validate_missing_tool_name
test_tool_config_validate_missing_target
test_tool_config_validate_missing_merge_hook
test_tool_config_validate_relative_target
test_tool_config_validate_hook_with_spaces
test_tool_config_validate_invalid_layer_source
test_tool_config_validate_layer_absolute_path

test_tool_config_add_layer
test_tool_config_add_multiple_layers
test_tool_config_set_layer_resolved

test_tool_config_getters
test_tool_config_layer_getters
test_tool_config_validate_outputs_errors_to_stderr

print_summary
