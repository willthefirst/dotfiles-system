#!/usr/bin/env bash
# test/unit/executor/builtins/test_source.sh
# Unit tests for executor/builtins/source.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../test_utils.sh"

# Source dependencies
source "$SCRIPT_DIR/../../../../lib/core/fs.sh"
source "$SCRIPT_DIR/../../../../lib/core/log.sh"

# Module under test
source "$SCRIPT_DIR/../../../../lib/executor/builtins/source.sh"

echo "Testing: executor/builtins/source"
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

# Test 1: source fails with no layers
test_source_no_layers() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:source"
    # No layers added

    declare -A result
    local rc=0
    builtin_merge_source config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "Should fail with no layers"
}

# Test 2: source generates source statements
test_source_generates_statements() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh/zshrc"

    fs_mock_set "/dotfiles/configs/zsh/zshrc" "export ZSH_THEME=robbyrussell"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "source" "Should contain source statement"
    assert_contains "$content" "/dotfiles/configs/zsh/zshrc" "Should reference layer path"
}

# Test 3: source adds layer comments
test_source_adds_comments() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "personal" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set "/dotfiles/configs/zsh" "content"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "# Layer: personal" "Should have layer comment"
}

# Test 4: source includes header
test_source_includes_header() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set "/dotfiles/configs/zsh" "content"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "Auto-generated" "Should have auto-generated header"
    assert_contains "$content" "dotfiles layering system" "Should mention layering system"
}

# Test 5: source handles multiple layers
test_source_multiple_layers() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_add_layer config "work" "local" "configs/zsh-work"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"
    tool_config_set_layer_resolved config 1 "/dotfiles/configs/zsh-work"

    fs_mock_set "/dotfiles/configs/zsh" "base config"
    fs_mock_set "/dotfiles/configs/zsh-work" "work config"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "# Layer: base" "Should have base layer"
    assert_contains "$content" "# Layer: work" "Should have work layer"
}

# Test 6: source uses safe source pattern
test_source_safe_pattern() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set "/dotfiles/configs/zsh" "content"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    # Should use [ -f "path" ] && source pattern for safety
    assert_contains "$content" '[ -f "' "Should use safe file check pattern"
}

# Test 7: source fails when no files found
test_source_no_files() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/missing"

    # No mock file set

    declare -A result
    local rc=0
    builtin_merge_source config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Should fail when no files found"
}

# Test 8: source backs up existing file
test_source_backup_existing() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set "/home/.zshrc" "old content"
    fs_mock_set "/dotfiles/configs/zsh" "new content"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "Auto-generated" "Should replace with new content"
}

# Test 9: source creates parent directories
test_source_creates_parent() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config/shell/init.sh" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    fs_mock_set "/dotfiles/configs/test" "content"

    declare -A result
    builtin_merge_source config result

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "mkdir:" "Should create parent directory"
}

# Test 10: source returns HookResult with files
test_source_returns_hook_result() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set "/dotfiles/configs/zsh" "content"

    declare -A result
    builtin_merge_source config result

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
    assert_contains "$files" "/home/.zshrc" "Result should include target"
}

# Test 11: source finds config in directory
test_source_finds_config_in_dir() {
    setup

    declare -A config
    tool_config_new config "zsh" "/home/.zshrc" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/zsh"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/zsh"

    fs_mock_set_dir "/dotfiles/configs/zsh"
    fs_mock_set "/dotfiles/configs/zsh/init" "init file content"

    declare -A result
    builtin_merge_source config result

    local content
    content=$(fs_read "/home/.zshrc")
    assert_contains "$content" "init" "Should find init file in directory"
}

# Test 12: source skips unresolved layers
test_source_skips_unresolved() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "builtin:source"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_add_layer config "missing" "local" "configs/missing"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"
    # Layer 1 not resolved

    fs_mock_set "/dotfiles/configs/test" "base content"

    declare -A result
    local rc=0
    builtin_merge_source config result || rc=$?

    assert_equals 0 "$rc" "Should succeed with some resolved layers"
}

# Run all tests
test_source_no_layers
test_source_generates_statements
test_source_adds_comments
test_source_includes_header
test_source_multiple_layers
test_source_safe_pattern
test_source_no_files
test_source_backup_existing
test_source_creates_parent
test_source_returns_hook_result
test_source_finds_config_in_dir
test_source_skips_unresolved

print_summary
