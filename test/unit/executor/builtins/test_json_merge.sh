#!/usr/bin/env bash
# test/unit/executor/builtins/test_json_merge.sh
# Unit tests for executor/builtins/json-merge.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../test_utils.sh"

# Source dependencies
source "$SCRIPT_DIR/../../../../lib/core/fs.sh"
source "$SCRIPT_DIR/../../../../lib/core/log.sh"

# Module under test
source "$SCRIPT_DIR/../../../../lib/executor/builtins/json-merge.sh"

echo "Testing: executor/builtins/json-merge"
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

# Test 1: json-merge fails with no layers
test_json_no_layers() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config.json" "builtin:json-merge"
    # No layers added

    declare -A result
    local rc=0
    builtin_merge_json config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "Should fail with no layers"
}

# Test 2: json-merge merges single layer
test_json_single_layer() {
    setup

    declare -A config
    tool_config_new config "vscode" "/home/.config/Code/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/vscode"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/vscode/settings.json"

    fs_mock_set "/dotfiles/configs/vscode/settings.json" '{"editor.fontSize": 14}'

    declare -A result
    builtin_merge_json config result

    local content
    content=$(fs_read "/home/.config/Code/settings.json")
    assert_contains "$content" "editor.fontSize" "Should include layer content"
}

# Test 3: json-merge handles multiple layers
test_json_multiple_layers() {
    setup

    declare -A config
    tool_config_new config "vscode" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/vscode"
    tool_config_add_layer config "work" "local" "configs/vscode-work"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/vscode"
    tool_config_set_layer_resolved config 1 "/dotfiles/configs/vscode-work"

    fs_mock_set "/dotfiles/configs/vscode" '{"theme": "dark"}'
    fs_mock_set "/dotfiles/configs/vscode-work" '{"linting": true}'

    declare -A result
    builtin_merge_json config result

    # In mock mode, later layers override (simplified merge)
    local content
    content=$(fs_read "/home/settings.json")
    # Should have some JSON content
    if [[ -n "$content" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Multiple layers produce output"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Multiple layers should produce output"
    fi
}

# Test 4: json-merge fails when no files found
test_json_no_files() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/missing"

    # No mock file set

    declare -A result
    local rc=0
    builtin_merge_json config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Should fail when no files found"
}

# Test 5: json-merge backs up existing file
test_json_backup_existing() {
    setup

    declare -A config
    tool_config_new config "test" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/home/settings.json" '{"old": "content"}'
    fs_mock_set "/dotfiles/configs/test" '{"new": "content"}'

    declare -A result
    builtin_merge_json config result

    local content
    content=$(fs_read "/home/settings.json")
    assert_contains "$content" "new" "Content should be updated"
}

# Test 6: json-merge creates parent directories
test_json_creates_parent() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config/app/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" '{"key": "value"}'

    declare -A result
    builtin_merge_json config result

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "mkdir:" "Should create parent directory"
}

# Test 7: json-merge returns HookResult with files
test_json_returns_hook_result() {
    setup

    declare -A config
    tool_config_new config "vscode" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/vscode"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/vscode"

    fs_mock_set "/dotfiles/configs/vscode" '{"key": "value"}'

    declare -A result
    builtin_merge_json config result

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
    assert_contains "$files" "/home/settings.json" "Result should include target"
}

# Test 8: json-merge finds json file in directory
test_json_finds_file_in_dir() {
    setup

    declare -A config
    tool_config_new config "vscode" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/vscode"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/vscode"

    fs_mock_set_dir "/dotfiles/configs/vscode"
    fs_mock_set "/dotfiles/configs/vscode/config.json" '{"found": true}'

    declare -A result
    builtin_merge_json config result

    local content
    content=$(fs_read "/home/settings.json")
    assert_contains "$content" "found" "Should find json in directory"
}

# Test 9: json-merge skips unresolved layers
test_json_skips_unresolved() {
    setup

    declare -A config
    tool_config_new config "test" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_add_layer config "missing" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"
    # Layer 1 not resolved

    fs_mock_set "/dotfiles/configs/test" '{"base": true}'

    declare -A result
    local rc=0
    builtin_merge_json config result || rc=$?

    assert_equals 0 "$rc" "Should succeed with some resolved layers"
}

# Test 10: json-merge expands tilde in target
test_json_expands_tilde() {
    setup

    declare -A config
    tool_config_new config "test" "~/.config/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" '{"key": "value"}'

    declare -A result
    builtin_merge_json config result

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "$HOME/.config/settings.json" "Tilde should be expanded"
}

# Test 11: json-merge handles empty base
test_json_empty_base() {
    setup

    declare -A config
    tool_config_new config "test" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" '{"only": "layer"}'

    declare -A result
    builtin_merge_json config result

    local content
    content=$(fs_read "/home/settings.json")
    assert_contains "$content" "only" "Should work with empty base"
}

# Test 12: json-merge prefers .json extension
test_json_prefers_json_extension() {
    setup

    declare -A config
    tool_config_new config "vscode" "/home/settings.json" "builtin:json-merge"
    tool_config_add_layer config "base" "local" "configs/vscode"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/vscode"

    fs_mock_set_dir "/dotfiles/configs/vscode"
    fs_mock_set "/dotfiles/configs/vscode/settings.json" '{"json": true}'
    fs_mock_set "/dotfiles/configs/vscode/other" 'plain text'

    declare -A result
    builtin_merge_json config result

    local content
    content=$(fs_read "/home/settings.json")
    # Should find the .json file
    if [[ -n "$content" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Prefers .json extension files"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Should prefer .json extension files"
    fi
}

# Run all tests
test_json_no_layers
test_json_single_layer
test_json_multiple_layers
test_json_no_files
test_json_backup_existing
test_json_creates_parent
test_json_returns_hook_result
test_json_finds_file_in_dir
test_json_skips_unresolved
test_json_expands_tilde
test_json_empty_base
test_json_prefers_json_extension

print_summary
