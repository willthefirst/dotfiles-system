#!/usr/bin/env bash
# test/unit/executor/test_runner.sh
# Unit tests for executor/runner.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source dependencies first
source "$SCRIPT_DIR/../../../lib/core/fs.sh"
source "$SCRIPT_DIR/../../../lib/core/log.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/executor/runner.sh"

echo "Testing: executor/runner"
echo ""

# Setup: Initialize mock mode before each test
setup() {
    fs_init "mock"
    fs_mock_reset
    declare -A log_cfg=([output]="mock")
    log_init log_cfg
    log_mock_reset
    strategy_clear
    runner_init "/dotfiles"
}

# Test 1: runner_init sets dotfiles dir
test_runner_init() {
    setup
    local dir
    dir=$(runner_get_dotfiles_dir)
    assert_equals "/dotfiles" "$dir" "runner_init should set dotfiles dir"
}

# Test 2: runner_init registers default builtins
test_runner_init_registers_builtins() {
    setup

    if strategy_exists "symlink"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: runner_init registers symlink strategy"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: runner_init should register symlink strategy"
    fi

    if strategy_exists "concat"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: runner_init registers concat strategy"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: runner_init should register concat strategy"
    fi

    if strategy_exists "source"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: runner_init registers source strategy"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: runner_init should register source strategy"
    fi

    if strategy_exists "json-merge"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: runner_init registers json-merge strategy"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: runner_init should register json-merge strategy"
    fi
}

# Test 3: runner_build_env builds correct env vars
test_runner_build_env() {
    setup

    # Create a ToolConfig with layers
    declare -A config
    tool_config_new config "git" "/home/user/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"

    declare -A env_vars
    runner_build_env config env_vars

    assert_equals "git" "${env_vars[TOOL]}" "TOOL should be git"
    assert_equals "/home/user/.gitconfig" "${env_vars[TARGET]}" "TARGET should be set"
    assert_equals "base" "${env_vars[LAYERS]}" "LAYERS should be base"
    assert_equals "/dotfiles/configs/git" "${env_vars[LAYER_PATHS]}" "LAYER_PATHS should be set"
    assert_equals "/dotfiles" "${env_vars[DOTFILES_DIR]}" "DOTFILES_DIR should be set"
}

# Test 4: runner_build_env handles multiple layers
test_runner_build_env_multiple_layers() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:concat"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_add_layer config "work" "local" "configs/git-work"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"
    tool_config_set_layer_resolved config 1 "/dotfiles/configs/git-work"

    declare -A env_vars
    runner_build_env config env_vars

    assert_equals "base:work" "${env_vars[LAYERS]}" "LAYERS should be colon-separated"
    assert_equals "/dotfiles/configs/git:/dotfiles/configs/git-work" "${env_vars[LAYER_PATHS]}" "LAYER_PATHS should be colon-separated"
}

# Test 5: runner_execute fails with empty hook spec
test_runner_execute_empty_spec() {
    setup

    declare -A config
    tool_config_new config "test" "/target" "builtin:symlink"

    declare -A result
    local rc=0
    runner_execute "" config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "runner_execute should fail with empty spec"
}

# Test 6: runner_execute handles builtin prefix
test_runner_execute_builtin() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"

    # Set up mock file for symlink
    fs_mock_set "/dotfiles/configs/git" "git config content"

    declare -A result
    local rc=0
    runner_execute "builtin:symlink" config result || rc=$?

    assert_equals 0 "$rc" "runner_execute builtin should succeed"

    if hook_result_is_success result; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: builtin:symlink returns success result"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: builtin:symlink should return success result"
    fi
}

# Test 7: runner_execute_builtin fails for unknown strategy
test_runner_execute_builtin_unknown() {
    setup

    declare -A config
    tool_config_new config "test" "/target" "builtin:unknown"

    declare -A result
    local rc=0
    runner_execute_builtin "unknown" config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Unknown builtin should fail"
}

# Test 8: runner_execute_script in mock mode
test_runner_execute_script_mock() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "merge.sh"
    tool_config_add_layer config "base" "local" "configs/test"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/test"

    # Set up mock script file
    fs_mock_set "/dotfiles/tools/test/merge.sh" "#!/bin/bash\necho test"

    declare -A result
    local rc=0
    runner_execute_script "merge.sh" config result || rc=$?

    # In mock mode, script execution is simulated
    assert_equals 0 "$rc" "Script execution in mock mode should succeed"
}

# Test 9: runner_execute_script fails for missing script
test_runner_execute_script_missing() {
    setup

    declare -A config
    tool_config_new config "test" "/home/.config" "nonexistent.sh"

    declare -A result
    local rc=0
    runner_execute_script "nonexistent.sh" config result 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "Missing script should fail"
}

# Test 10: runner_run_merge calls correct hook
test_runner_run_merge() {
    setup

    declare -A config
    tool_config_new config "git" "/home/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_set_layer_resolved config 0 "/dotfiles/configs/git"

    fs_mock_set "/dotfiles/configs/git" "content"

    declare -A result
    local rc=0
    runner_run_merge config result || rc=$?

    assert_equals 0 "$rc" "runner_run_merge should succeed"
}

# Test 11: runner_run_merge fails without hook
test_runner_run_merge_no_hook() {
    setup

    declare -A config
    config=([tool_name]="test" [target]="/target" [merge_hook]="" [layer_count]=0)

    declare -A result
    local rc=0
    runner_run_merge config result 2>/dev/null || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "runner_run_merge should fail without hook"
}

# Test 12: runner_run_install with no install hook succeeds
test_runner_run_install_no_hook() {
    setup

    declare -A config
    tool_config_new config "test" "/target" "builtin:symlink"
    # No install hook set

    declare -A result
    local rc=0
    runner_run_install config result || rc=$?

    assert_equals 0 "$rc" "runner_run_install should succeed with no hook"

    if hook_result_is_success result; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: No install hook returns success"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: No install hook should return success"
    fi
}

# Test 13: runner_init expands tilde
test_runner_init_expands_tilde() {
    fs_init "mock"
    strategy_clear
    runner_init "~/dotfiles"

    local dir
    dir=$(runner_get_dotfiles_dir)
    assert_contains "$dir" "$HOME" "Tilde should be expanded"
}

# Test 14: runner_build_env expands tilde in target
test_runner_build_env_expands_tilde() {
    setup

    declare -A config
    tool_config_new config "test" "~/.config" "builtin:symlink"

    declare -A env_vars
    runner_build_env config env_vars

    assert_contains "${env_vars[TARGET]}" "$HOME" "TARGET tilde should be expanded"
}

# Run all tests
test_runner_init
test_runner_init_registers_builtins
test_runner_build_env
test_runner_build_env_multiple_layers
test_runner_execute_empty_spec
test_runner_execute_builtin
test_runner_execute_builtin_unknown
test_runner_execute_script_mock
test_runner_execute_script_missing
test_runner_run_merge
test_runner_run_merge_no_hook
test_runner_run_install_no_hook
test_runner_init_expands_tilde
test_runner_build_env_expands_tilde

print_summary
