#!/usr/bin/env bash
# test/unit/contracts/test_machine_config.sh
# Unit tests for contracts/machine_config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/contracts/machine_config.sh"

echo "Testing: contracts/machine_config"
echo ""

# ============================================================================
# Constructor Tests
# ============================================================================

test_machine_config_new_creates_config() {
    declare -A config
    machine_config_new config "work-macbook"

    assert_equals "work-macbook" "${config[profile_name]}" "profile_name should be set"
    assert_equals "0" "${config[tool_count]}" "tool_count should be 0 initially"
}

test_machine_config_new_with_underscores() {
    declare -A config
    machine_config_new config "personal_laptop"

    assert_equals "personal_laptop" "${config[profile_name]}" "profile_name with underscores"
}

# ============================================================================
# Validation Tests - Valid Cases
# ============================================================================

test_machine_config_validate_valid_empty() {
    declare -A config
    machine_config_new config "test-profile"

    machine_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "empty config with valid profile_name should pass"
}

test_machine_config_validate_valid_with_tools() {
    declare -A config
    machine_config_new config "work-macbook"
    machine_config_add_tool config "git"
    machine_config_set_tool_layers config "git" "base work"
    machine_config_add_tool config "nvim"
    machine_config_set_tool_layers config "nvim" "base"

    machine_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "config with tools and layers should pass"
}

test_machine_config_validate_profile_with_numbers() {
    declare -A config
    machine_config_new config "macbook-pro-2023"

    machine_config_validate config
    local rc=$?

    assert_equals "$E_OK" "$rc" "profile name with numbers should be valid"
}

# ============================================================================
# Validation Tests - Invalid Cases
# ============================================================================

test_machine_config_validate_missing_profile_name() {
    declare -A config
    machine_config_new config ""

    machine_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing profile_name should fail"
}

test_machine_config_validate_invalid_profile_name_spaces() {
    declare -A config
    machine_config_new config "work macbook"

    machine_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "profile_name with spaces should fail"
}

test_machine_config_validate_invalid_profile_name_special() {
    declare -A config
    machine_config_new config "work@home"

    machine_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "profile_name with special chars should fail"
}

test_machine_config_validate_tool_without_layers() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    # Not setting layers for git

    machine_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "tool without layers should fail validation"
}

test_machine_config_validate_invalid_tool_name() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git tool"
    machine_config_set_tool_layers config "git tool" "base"

    machine_config_validate config 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "tool name with spaces should fail"
}

# ============================================================================
# Tool Management Tests
# ============================================================================

test_machine_config_add_tool() {
    declare -A config
    machine_config_new config "test-profile"

    machine_config_add_tool config "git"

    assert_equals "1" "${config[tool_count]}" "tool_count should be 1"
    assert_equals "git" "${config[tool_0]}" "tool should be stored"
}

test_machine_config_add_multiple_tools() {
    declare -A config
    machine_config_new config "test-profile"

    machine_config_add_tool config "git"
    machine_config_add_tool config "nvim"
    machine_config_add_tool config "zsh"

    assert_equals "3" "${config[tool_count]}" "tool_count should be 3"
    assert_equals "git" "${config[tool_0]}" "first tool"
    assert_equals "nvim" "${config[tool_1]}" "second tool"
    assert_equals "zsh" "${config[tool_2]}" "third tool"
}

test_machine_config_set_tool_layers() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"

    machine_config_set_tool_layers config "git" "base work personal"

    assert_equals "base work personal" "${config[layers_git]}" "layers should be stored"
}

test_machine_config_set_tool_layers_multiple_tools() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    machine_config_add_tool config "nvim"

    machine_config_set_tool_layers config "git" "base work"
    machine_config_set_tool_layers config "nvim" "base"

    assert_equals "base work" "${config[layers_git]}" "git layers"
    assert_equals "base" "${config[layers_nvim]}" "nvim layers"
}

# ============================================================================
# Getter Tests
# ============================================================================

test_machine_config_get_profile_name() {
    declare -A config
    machine_config_new config "work-macbook"

    local name
    name=$(machine_config_get_profile_name config)

    assert_equals "work-macbook" "$name" "get_profile_name should return profile name"
}

test_machine_config_get_tool_count() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    machine_config_add_tool config "nvim"

    local count
    count=$(machine_config_get_tool_count config)

    assert_equals "2" "$count" "get_tool_count should return 2"
}

test_machine_config_get_tool() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    machine_config_add_tool config "nvim"

    local tool0 tool1
    tool0=$(machine_config_get_tool config 0)
    tool1=$(machine_config_get_tool config 1)

    assert_equals "git" "$tool0" "get_tool 0"
    assert_equals "nvim" "$tool1" "get_tool 1"
}

test_machine_config_get_tool_layers() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    machine_config_set_tool_layers config "git" "base work"

    local layers
    layers=$(machine_config_get_tool_layers config "git")

    assert_equals "base work" "$layers" "get_tool_layers should return layers"
}

# ============================================================================
# has_tool Tests
# ============================================================================

test_machine_config_has_tool_true() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"
    machine_config_add_tool config "nvim"

    machine_config_has_tool config "git"
    local rc=$?

    assert_equals "0" "$rc" "has_tool should return 0 for existing tool"
}

test_machine_config_has_tool_false() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"

    machine_config_has_tool config "nvim"
    local rc=$?

    assert_equals "1" "$rc" "has_tool should return 1 for non-existent tool"
}

test_machine_config_has_tool_empty() {
    declare -A config
    machine_config_new config "test-profile"

    machine_config_has_tool config "git"
    local rc=$?

    assert_equals "1" "$rc" "has_tool should return 1 for empty config"
}

# ============================================================================
# Error Message Tests
# ============================================================================

test_machine_config_validate_outputs_errors_to_stderr() {
    declare -A config
    machine_config_new config ""

    local stderr_output
    stderr_output=$(machine_config_validate config 2>&1 >/dev/null) || true

    assert_contains "$stderr_output" "validation failed" "should output failure message"
    assert_contains "$stderr_output" "profile_name is required" "should list error"
}

test_machine_config_validate_missing_layers_error() {
    declare -A config
    machine_config_new config "test-profile"
    machine_config_add_tool config "git"

    local stderr_output
    stderr_output=$(machine_config_validate config 2>&1 >/dev/null) || true

    assert_contains "$stderr_output" "no layers defined for tool: git" "should report missing layers"
}

# ============================================================================
# Run Tests
# ============================================================================

test_machine_config_new_creates_config
test_machine_config_new_with_underscores

test_machine_config_validate_valid_empty
test_machine_config_validate_valid_with_tools
test_machine_config_validate_profile_with_numbers

test_machine_config_validate_missing_profile_name
test_machine_config_validate_invalid_profile_name_spaces
test_machine_config_validate_invalid_profile_name_special
test_machine_config_validate_tool_without_layers
test_machine_config_validate_invalid_tool_name

test_machine_config_add_tool
test_machine_config_add_multiple_tools
test_machine_config_set_tool_layers
test_machine_config_set_tool_layers_multiple_tools

test_machine_config_get_profile_name
test_machine_config_get_tool_count
test_machine_config_get_tool
test_machine_config_get_tool_layers

test_machine_config_has_tool_true
test_machine_config_has_tool_false
test_machine_config_has_tool_empty

test_machine_config_validate_outputs_errors_to_stderr
test_machine_config_validate_missing_layers_error

print_summary
