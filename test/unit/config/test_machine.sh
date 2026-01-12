#!/usr/bin/env bash
# test/unit/config/test_machine.sh
# Unit tests for config/machine.sh (JSON parsing only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source fs module first (for mock support)
source "$SCRIPT_DIR/../../../lib/core/fs.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/config/machine.sh"

echo "Testing: config/machine"
echo ""

# ============================================================================
# Setup
# ============================================================================

setup() {
    fs_init "mock"
    fs_mock_reset
}

# ============================================================================
# config_get_profile_name Tests
# ============================================================================

test_get_profile_name_json() {
    local result
    result=$(config_get_profile_name "/path/to/machines/stripe-mac.json")

    assert_equals "stripe-mac" "$result" "should extract profile name"
}

test_get_profile_name_with_extension() {
    local result
    result=$(config_get_profile_name "machines/personal-mac.json")

    assert_equals "personal-mac" "$result" "should strip .json extension"
}

test_get_profile_name_no_path() {
    local result
    result=$(config_get_profile_name "work.json")

    assert_equals "work" "$result" "should handle just filename"
}

# ============================================================================
# JSON Profile Parsing Tests
# ============================================================================

test_load_machine_profile_json_basic() {
    setup
    fs_mock_set "/machines/test.json" '{
        "name": "test",
        "tools": {
            "git": ["base"],
            "zsh": ["base"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/test.json" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "test" "$(machine_config_get_profile_name config)" "profile name"
    assert_equals "2" "$(machine_config_get_tool_count config)" "tool count"
}

test_load_machine_profile_json_with_layers() {
    setup
    fs_mock_set "/machines/work.json" '{
        "name": "work",
        "tools": {
            "git": ["base", "stripe"],
            "nvim": ["base", "stripe", "personal"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/work.json" config

    assert_equals "base stripe" "$(machine_config_get_tool_layers config "git")" "git layers"
    assert_equals "base stripe personal" "$(machine_config_get_tool_layers config "nvim")" "nvim layers"
}

test_load_machine_profile_json_invalid_syntax() {
    setup
    fs_mock_set "/machines/broken.json" '{ "name": "broken", invalid json }'

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/broken.json" config 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "invalid JSON should fail"
}

test_load_machine_profile_json_no_tools() {
    setup
    fs_mock_set "/machines/empty.json" '{
        "name": "empty"
    }'

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/empty.json" config 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing tools should fail"
}

test_load_machine_profile_json_empty_tools() {
    setup
    fs_mock_set "/machines/empty-tools.json" '{
        "name": "empty-tools",
        "tools": {}
    }'

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/empty-tools.json" config 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "empty tools object should fail"
}

test_load_machine_profile_json_not_found() {
    setup
    # No mock file set

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/nonexistent.json" config || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND"
}

test_load_machine_profile_json_fallback_name() {
    setup
    # JSON file without "name" field - should use filename
    fs_mock_set "/machines/stripe-mac.json" '{
        "tools": {
            "git": ["base"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/stripe-mac.json" config

    assert_equals "stripe-mac" "$(machine_config_get_profile_name config)" "should use filename when name missing"
}

test_load_machine_profile_json_real_format() {
    setup
    # Test with format matching the schema
    fs_mock_set "/machines/stripe-mac.json" '{
        "$schema": "../lib/dotfiles-system/schemas/machine.schema.json",
        "name": "stripe-mac",
        "description": "Stripe Mac configuration - base + stripe layers",
        "tools": {
            "git": ["base", "stripe"],
            "zsh": ["base", "stripe"],
            "nvim": ["base"],
            "ghostty": ["base"],
            "vscode": ["base", "stripe"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/stripe-mac.json" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should parse real JSON format"
    assert_equals "stripe-mac" "$(machine_config_get_profile_name config)" "profile name"
    assert_equals "5" "$(machine_config_get_tool_count config)" "tool count"
    assert_equals "base stripe" "$(machine_config_get_tool_layers config "git")" "git layers"
    assert_equals "base stripe" "$(machine_config_get_tool_layers config "zsh")" "zsh layers"
    assert_equals "base" "$(machine_config_get_tool_layers config "nvim")" "nvim layers"
}

test_load_machine_profile_json_has_tool() {
    setup
    fs_mock_set "/machines/test.json" '{
        "name": "test",
        "tools": {
            "git": ["base"],
            "zsh": ["base"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/test.json" config

    local has_git=0
    machine_config_has_tool config "git" || has_git=$?

    local has_nonexistent=0
    machine_config_has_tool config "nonexistent" || has_nonexistent=$?

    assert_equals "0" "$has_git" "should have git"
    assert_equals "1" "$has_nonexistent" "should not have nonexistent"
}

test_load_machine_profile_single_tool() {
    setup
    fs_mock_set "/machines/minimal.json" '{
        "name": "minimal",
        "tools": {
            "git": ["base"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/minimal.json" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should handle single tool"
    assert_equals "1" "$(machine_config_get_tool_count config)" "tool count"
    assert_equals "base" "$(machine_config_get_tool_layers config "git")" "git layers"
}

test_load_machine_profile_many_tools() {
    setup
    fs_mock_set "/machines/full.json" '{
        "name": "full",
        "tools": {
            "git": ["base", "stripe"],
            "zsh": ["base", "stripe"],
            "nvim": ["base"],
            "ssh": ["base", "stripe"],
            "ghostty": ["base"],
            "karabiner": ["base"],
            "claude": ["base"],
            "vscode": ["base", "stripe"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/full.json" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should handle many tools"
    assert_equals "8" "$(machine_config_get_tool_count config)" "tool count"
}

test_load_machine_profile_three_layers() {
    setup
    fs_mock_set "/machines/devbox.json" '{
        "name": "devbox",
        "tools": {
            "zsh": ["base", "stripe", "devbox"]
        }
    }'

    declare -A config
    config_load_machine_profile "/machines/devbox.json" config

    assert_equals "base stripe devbox" "$(machine_config_get_tool_layers config "zsh")" "should support 3 layers"
}

# ============================================================================
# Run Tests
# ============================================================================

# Profile name extraction
test_get_profile_name_json
test_get_profile_name_with_extension
test_get_profile_name_no_path

# JSON profile loading
test_load_machine_profile_json_basic
test_load_machine_profile_json_with_layers
test_load_machine_profile_json_invalid_syntax
test_load_machine_profile_json_no_tools
test_load_machine_profile_json_empty_tools
test_load_machine_profile_json_not_found
test_load_machine_profile_json_fallback_name
test_load_machine_profile_json_real_format
test_load_machine_profile_json_has_tool
test_load_machine_profile_single_tool
test_load_machine_profile_many_tools
test_load_machine_profile_three_layers

print_summary
