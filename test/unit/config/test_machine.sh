#!/usr/bin/env bash
# test/unit/config/test_machine.sh
# Unit tests for config/machine.sh

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

test_get_profile_name_simple() {
    local result
    result=$(config_get_profile_name "/path/to/machines/stripe-mac.sh")

    assert_equals "stripe-mac" "$result" "should extract profile name"
}

test_get_profile_name_with_extension() {
    local result
    result=$(config_get_profile_name "machines/personal-mac.sh")

    assert_equals "personal-mac" "$result" "should strip .sh extension"
}

test_get_profile_name_no_path() {
    local result
    result=$(config_get_profile_name "work.sh")

    assert_equals "work" "$result" "should handle just filename"
}

# ============================================================================
# config_parse_bash_array Tests
# ============================================================================

test_parse_bash_array_single_line() {
    local content='TOOLS=(git zsh nvim)'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "git zsh nvim" "$result" "should parse single-line array"
}

test_parse_bash_array_multi_line() {
    local content='TOOLS=(
    git
    zsh
    nvim
)'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "git zsh nvim" "$result" "should parse multi-line array"
}

test_parse_bash_array_with_comments() {
    local content='# Comment before
TOOLS=(git zsh)  # inline comment
# Comment after'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "git zsh" "$result" "should handle comments"
}

test_parse_bash_array_layers() {
    local content='git_layers=(base stripe)'

    local result
    result=$(config_parse_bash_array "$content" "git_layers")

    assert_equals "base stripe" "$result" "should parse layer arrays"
}

test_parse_bash_array_not_found() {
    local content='OTHER=(foo bar)'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "" "$result" "should return empty for not found"
}

test_parse_bash_array_with_quotes() {
    local content='TOOLS=("git" "zsh")'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "git zsh" "$result" "should strip quotes"
}

test_parse_bash_array_single_element() {
    local content='TOOLS=(git)'

    local result
    result=$(config_parse_bash_array "$content" "TOOLS")

    assert_equals "git" "$result" "should handle single element"
}

test_parse_bash_array_multiple_arrays() {
    local content='TOOLS=(git zsh)
git_layers=(base stripe)
zsh_layers=(base)'

    local tools layers1 layers2
    tools=$(config_parse_bash_array "$content" "TOOLS")
    layers1=$(config_parse_bash_array "$content" "git_layers")
    layers2=$(config_parse_bash_array "$content" "zsh_layers")

    assert_equals "git zsh" "$tools" "TOOLS array"
    assert_equals "base stripe" "$layers1" "git_layers array"
    assert_equals "base" "$layers2" "zsh_layers array"
}

# ============================================================================
# config_load_machine_profile Tests
# ============================================================================

test_load_machine_profile_basic() {
    setup
    fs_mock_set "/machines/test.sh" 'TOOLS=(git zsh)
git_layers=(base)
zsh_layers=(base)'

    declare -A config
    config_load_machine_profile "/machines/test.sh" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "test" "$(machine_config_get_profile_name config)" "profile name"
    assert_equals "2" "$(machine_config_get_tool_count config)" "tool count"
}

test_load_machine_profile_with_layers() {
    setup
    fs_mock_set "/machines/work.sh" 'TOOLS=(git nvim)
git_layers=(base stripe)
nvim_layers=(base stripe personal)'

    declare -A config
    config_load_machine_profile "/machines/work.sh" config

    assert_equals "base stripe" "$(machine_config_get_tool_layers config "git")" "git layers"
    assert_equals "base stripe personal" "$(machine_config_get_tool_layers config "nvim")" "nvim layers"
}

test_load_machine_profile_not_found() {
    setup
    # No mock file set

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/nonexistent.sh" config || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND"
}

test_load_machine_profile_no_tools() {
    setup
    fs_mock_set "/machines/empty.sh" '# No TOOLS defined'

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/empty.sh" config 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing TOOLS should fail"
}

test_load_machine_profile_missing_layers() {
    setup
    fs_mock_set "/machines/broken.sh" 'TOOLS=(git zsh)
git_layers=(base)'
    # Note: zsh_layers is missing

    declare -A config
    local rc=0
    config_load_machine_profile "/machines/broken.sh" config 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing layers should fail validation"
}

test_load_machine_profile_real_format() {
    setup
    # Test with a format like the actual machine profiles
    fs_mock_set "/machines/stripe-mac.sh" '# machines/stripe-mac.sh
# Stripe Mac configuration - base + stripe layers

TOOLS=(
    git
    zsh
    nvim
)

# Layer assignments (base + stripe for work machine)
git_layers=(base stripe)
zsh_layers=(base stripe)
nvim_layers=(base)'

    declare -A config
    config_load_machine_profile "/machines/stripe-mac.sh" config
    local rc=$?

    assert_equals "$E_OK" "$rc" "should parse real format"
    assert_equals "stripe-mac" "$(machine_config_get_profile_name config)" "profile name"
    assert_equals "3" "$(machine_config_get_tool_count config)" "tool count"
    assert_equals "base stripe" "$(machine_config_get_tool_layers config "git")" "git layers"
    assert_equals "base stripe" "$(machine_config_get_tool_layers config "zsh")" "zsh layers"
    assert_equals "base" "$(machine_config_get_tool_layers config "nvim")" "nvim layers"
}

test_load_machine_profile_has_tool() {
    setup
    fs_mock_set "/machines/test.sh" 'TOOLS=(git zsh)
git_layers=(base)
zsh_layers=(base)'

    declare -A config
    config_load_machine_profile "/machines/test.sh" config

    local has_git=0
    machine_config_has_tool config "git" || has_git=$?

    local has_nonexistent=0
    machine_config_has_tool config "nonexistent" || has_nonexistent=$?

    assert_equals "0" "$has_git" "should have git"
    assert_equals "1" "$has_nonexistent" "should not have nonexistent"
}

test_load_machine_profile_get_tools() {
    setup
    fs_mock_set "/machines/test.sh" 'TOOLS=(git zsh nvim)
git_layers=(base)
zsh_layers=(base)
nvim_layers=(base)'

    declare -A config
    config_load_machine_profile "/machines/test.sh" config

    assert_equals "git" "$(machine_config_get_tool config 0)" "first tool"
    assert_equals "zsh" "$(machine_config_get_tool config 1)" "second tool"
    assert_equals "nvim" "$(machine_config_get_tool config 2)" "third tool"
}

# ============================================================================
# Run Tests
# ============================================================================

# Profile name extraction
test_get_profile_name_simple
test_get_profile_name_with_extension
test_get_profile_name_no_path

# Bash array parsing
test_parse_bash_array_single_line
test_parse_bash_array_multi_line
test_parse_bash_array_with_comments
test_parse_bash_array_layers
test_parse_bash_array_not_found
test_parse_bash_array_with_quotes
test_parse_bash_array_single_element
test_parse_bash_array_multiple_arrays

# Full profile loading
test_load_machine_profile_basic
test_load_machine_profile_with_layers
test_load_machine_profile_not_found
test_load_machine_profile_no_tools
test_load_machine_profile_missing_layers
test_load_machine_profile_real_format
test_load_machine_profile_has_tool
test_load_machine_profile_get_tools

print_summary
