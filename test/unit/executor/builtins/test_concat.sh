#!/usr/bin/env bash
# test/unit/executor/builtins/test_concat.sh
# Unit tests for executor/builtins/concat.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../test_utils.sh"

# Source dependencies
source "$SCRIPT_DIR/../../../../lib/core/fs.sh"
source "$SCRIPT_DIR/../../../../lib/core/log.sh"

# Module under test
source "$SCRIPT_DIR/../../../../lib/executor/builtins/concat.sh"

echo "Testing: executor/builtins/concat"
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

# Test 1: concat fails with no layers
test_concat_no_layers() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:concat"
    # No layers added

    declare -A result
    local rc=0
    builtin_merge_concat config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "Should fail with no layers"
}

# Test 2: concat merges single layer
test_concat_single_layer() {
    setup

    declare -A config
    tool_config_new config "bash" "/home/.bashrc" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/bash"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/bash/bashrc"

    fs_mock_set "/dotfiles/configs/bash/bashrc" "export PATH=/usr/bin"

    declare -A result
    builtin_merge_concat config result

    local content
    content=$(fs_read "/home/.bashrc")
    assert_contains "$content" "export PATH=/usr/bin" "Content should include layer"
    assert_contains "$content" "Layer: base" "Content should have layer header"
}

# Test 3: concat merges multiple layers in order
test_concat_multiple_layers() {
    setup

    declare -A config
    tool_config_new config "bash" "/home/.bashrc" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/bash"
    tool_config_add_layer config "work" "local" "configs/bash-work"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/bash"
    tool_config_set_layer_resolved config 1 "/dotfiles/configs/bash-work"

    fs_mock_set "/dotfiles/configs/bash" "# Base config"
    fs_mock_set "/dotfiles/configs/bash-work" "# Work config"

    declare -A result
    builtin_merge_concat config result

    local content
    content=$(fs_read "/home/.bashrc")
    assert_contains "$content" "# Base config" "Should include base"
    assert_contains "$content" "# Work config" "Should include work"
}

# Test 4: concat adds layer headers
test_concat_layer_headers() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:concat"
    tool_config_add_layer config "personal" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test/config"

    fs_mock_set "/dotfiles/configs/test/config" "content"

    declare -A result
    builtin_merge_concat config result

    local content
    content=$(fs_read "/home/.config")
    assert_contains "$content" "# === Layer: personal ===" "Should have layer header"
    assert_contains "$content" "# Source:" "Should have source comment"
}

# Test 5: concat fails when no files found
test_concat_no_files() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/missing"

    # No mock file set - layer exists but no config file

    declare -A result
    local rc=0
    builtin_merge_concat config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Should fail when no files found"
}

# Test 6: concat skips unresolved layers
test_concat_skips_unresolved() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_add_layer config "missing" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"
    # Layer 1 not resolved

    fs_mock_set "/dotfiles/configs/test" "base content"

    declare -A result
    local rc=0
    builtin_merge_concat config result || rc=$?

    assert_equals 0 "$rc" "Should succeed with some resolved layers"

    local content
    content=$(fs_read "/home/.config")
    assert_contains "$content" "base content" "Should include resolved layer"
}

# Test 7: concat backs up existing file
test_concat_backup_existing() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/home/.config" "old content"
    fs_mock_set "/dotfiles/configs/test" "new content"

    declare -A result
    builtin_merge_concat config result

    # File should be replaced
    local content
    content=$(fs_read "/home/.config")
    assert_contains "$content" "new content" "Content should be new"
}

# Test 8: concat creates parent directories
test_concat_creates_parent() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config/app/config" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" "content"

    declare -A result
    builtin_merge_concat config result

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "mkdir:" "Should create parent directory"
}

# Test 9: concat returns HookResult with files
test_concat_returns_hook_result() {
    setup

    declare -A config
    tool_config_new config "bash" "/home/.bashrc" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/bash"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/bash"

    fs_mock_set "/dotfiles/configs/bash" "content"

    declare -A result
    builtin_merge_concat config result

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
    assert_contains "$files" "/home/.bashrc" "Result should include target"
}

# Test 10: concat finds config in directory
test_concat_finds_config_in_dir() {
    setup

    declare -A config
    tool_config_new config "bash" "/home/.bashrc" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/bash"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/bash"

    fs_mock_set_dir "/dotfiles/configs/bash"
    fs_mock_set "/dotfiles/configs/bash/config" "from config file"

    declare -A result
    builtin_merge_concat config result

    local content
    content=$(fs_read "/home/.bashrc")
    assert_contains "$content" "from config file" "Should find config in directory"
}

# Test 11: concat expands tilde in target
test_concat_expands_tilde() {
    setup

    declare -A config
    tool_config_new config "test" "~/.config" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" "content"

    declare -A result
    builtin_merge_concat config result

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "$HOME/.config" "Tilde should be expanded"
}

# Run all tests
test_concat_no_layers
test_concat_single_layer
test_concat_multiple_layers
test_concat_layer_headers
test_concat_no_files
test_concat_skips_unresolved
test_concat_backup_existing
test_concat_creates_parent
test_concat_returns_hook_result
test_concat_finds_config_in_dir
test_concat_expands_tilde

print_summary
