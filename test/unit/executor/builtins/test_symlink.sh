#!/usr/bin/env bash
# test/unit/executor/builtins/test_symlink.sh
# Unit tests for executor/builtins/symlink.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../test_utils.sh"

# Source dependencies
source "$SCRIPT_DIR/../../../../lib/core/fs.sh"
source "$SCRIPT_DIR/../../../../lib/core/log.sh"

# Module under test
source "$SCRIPT_DIR/../../../../lib/executor/builtins/symlink.sh"

echo "Testing: executor/builtins/symlink"
echo ""

# Setup: Initialize mock mode before each test
setup() {
    fs_init "mock"
    fs_mock_reset
    declare -A log_cfg=([output]="mock")
    log_init log_cfg
    log_mock_reset
    declare -A backup_cfg=([dir]="/backup")
    backup_init backup_cfg
}

# Test 1: symlink fails with no layers
test_symlink_no_layers() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:symlink"
    # No layers added

    declare -A result
    local rc=0
    builtin_merge_symlink config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "Should fail with no layers"
}

# Test 2: symlink creates link to file layer
test_symlink_file_layer() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git/gitconfig"

    # Set up mock file
    fs_mock_set "/dotfiles/configs/git/gitconfig" "[user]\nname = test"

    declare -A result
    local rc=0
    builtin_merge_symlink config result || rc=$?

    assert_equals 0 "$rc" "Should succeed"

    if fs_is_symlink "/home/.gitconfig"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Target is a symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Target should be a symlink"
    fi

    local target
    target=$(fs_readlink "/home/.gitconfig")
    assert_equals "/dotfiles/configs/git/gitconfig" "$target" "Symlink should point to source"
}

# Test 3: symlink creates link to directory layer
test_symlink_directory_layer() {
    setup

    declare -A config
    tool_config_new config "nvim" "/home/.config/nvim" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/nvim"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/nvim"

    # Set up mock directory
    fs_mock_set_dir "/dotfiles/configs/nvim"
    fs_mock_set "/dotfiles/configs/nvim/init.lua" "require('config')"

    declare -A result
    local rc=0
    builtin_merge_symlink config result || rc=$?

    assert_equals 0 "$rc" "Should succeed"

    if fs_is_symlink "/home/.config/nvim"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Target dir is a symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Target dir should be a symlink"
    fi
}

# Test 4: symlink uses last layer only
test_symlink_uses_last_layer() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/base"
    tool_config_add_layer config "work" "local" "configs/work"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/base"
    tool_config_set_layer_resolved config 1 "/dotfiles/configs/work"

    fs_mock_set "/dotfiles/configs/base" "base content"
    fs_mock_set "/dotfiles/configs/work" "work content"

    declare -A result
    builtin_merge_symlink config result

    local target
    target=$(fs_readlink "/home/.config")
    assert_equals "/dotfiles/configs/work" "$target" "Should use last layer"
}

# Test 5: symlink fails for missing layer
test_symlink_missing_layer() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/missing"

    # Don't create the mock file - it's missing

    declare -A result
    local rc=0
    builtin_merge_symlink config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Should fail for missing layer"
}

# Test 6: symlink backs up existing file
test_symlink_backup_existing() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    # Existing file at target
    fs_mock_set "/home/.config" "old content"
    fs_mock_set "/dotfiles/configs/test" "new content"

    declare -A result
    builtin_merge_symlink config result

    # Check backup was created
    local calls
    calls=$(fs_mock_calls)
    # Target should have been backed up before replacement
    if fs_is_symlink "/home/.config"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Existing file was replaced with symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Existing file should be replaced with symlink"
    fi
}

# Test 7: symlink returns HookResult with files
test_symlink_returns_hook_result() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"

    fs_mock_set "/dotfiles/configs/git" "content"

    declare -A result
    builtin_merge_symlink config result

    if hook_result_is_success result; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Result is success"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Result should be success"
    fi

    local files
    files=$(hook_result_get_files_modified result)
    assert_contains "$files" "/home/.gitconfig" "Result should include target file"
}

# Test 8: symlink creates parent directories
test_symlink_creates_parent_dirs() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config/deep/path/.file" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" "content"

    declare -A result
    builtin_merge_symlink config result

    # Check mkdir was called for parent
    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "mkdir:" "Should create parent directory"
}

# Test 9: symlink expands tilde in target
test_symlink_expands_tilde() {
    setup

    declare -A config
    tool_config_new config "test" "~/.config" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" "content"

    declare -A result
    builtin_merge_symlink config result

    # The symlink should be created at expanded path
    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "$HOME/.config" "Tilde should be expanded"
}

# Test 10: symlink finds config file in directory
test_symlink_finds_config_in_dir() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"

    # Layer is a directory with config file
    fs_mock_set_dir "/dotfiles/configs/git"
    fs_mock_set "/dotfiles/configs/git/config" "git config"

    declare -A result
    builtin_merge_symlink config result

    # Symlink should point to the config file or directory
    if fs_is_symlink "/home/.gitconfig"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Symlink created from directory layer"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Symlink should be created from directory layer"
    fi
}

# Test 11: symlink fails when layer not resolved
test_symlink_layer_not_resolved() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/test"
    # Don't call tool_config_set_layer_resolved

    declare -A result
    local rc=0
    builtin_merge_symlink config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Should fail when layer not resolved"
}

# Run all tests
test_symlink_no_layers
test_symlink_file_layer
test_symlink_directory_layer
test_symlink_uses_last_layer
test_symlink_missing_layer
test_symlink_backup_existing
test_symlink_returns_hook_result
test_symlink_creates_parent_dirs
test_symlink_expands_tilde
test_symlink_finds_config_in_dir
test_symlink_layer_not_resolved

print_summary
