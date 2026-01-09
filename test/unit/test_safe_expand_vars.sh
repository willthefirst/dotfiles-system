#!/usr/bin/env bash
# test/unit/test_safe_expand_vars.sh
# Unit tests for safe_expand_vars function

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"
source "$SCRIPT_DIR/../../lib/utils.sh"

echo "Testing: safe_expand_vars"
echo ""

# Test 1: Expand HOME variable with braces
test_expand_home_braces() {
    local result
    result=$(safe_expand_vars '${HOME}/.config')
    assert_equals "$HOME/.config" "$result" "Should expand \${HOME} with braces"
}

# Test 2: Expand HOME variable without braces
test_expand_home_no_braces() {
    local result
    result=$(safe_expand_vars '$HOME/.config')
    assert_equals "$HOME/.config" "$result" "Should expand \$HOME without braces"
}

# Test 3: Block command injection with $()
test_block_command_substitution() {
    local result
    result=$(safe_expand_vars '$(whoami)')
    assert_equals '$(whoami)' "$result" "Should NOT execute \$(command)"
}

# Test 4: Block command injection with backticks
test_block_backtick_injection() {
    local result
    result=$(safe_expand_vars '`whoami`')
    assert_equals '`whoami`' "$result" "Should NOT execute backtick commands"
}

# Test 5: Block dangerous rm command
test_block_dangerous_rm() {
    local result
    result=$(safe_expand_vars '$(rm -rf /)')
    assert_equals '$(rm -rf /)' "$result" "Should NOT execute dangerous rm command"
}

# Test 6: Expand multiple variables
test_expand_multiple_vars() {
    export TEST_VAR="testvalue"
    local result
    result=$(safe_expand_vars '${HOME}/${TEST_VAR}/file')
    assert_equals "$HOME/testvalue/file" "$result" "Should expand multiple variables"
    unset TEST_VAR
}

# Test 7: Handle undefined variable gracefully
test_undefined_var() {
    unset UNDEFINED_VAR 2>/dev/null || true
    local result
    result=$(safe_expand_vars '${UNDEFINED_VAR}/path')
    assert_equals "/path" "$result" "Should handle undefined var as empty string"
}

# Test 8: No expansion needed
test_no_expansion() {
    local result
    result=$(safe_expand_vars '/plain/path/no/vars')
    assert_equals '/plain/path/no/vars' "$result" "Should return unchanged if no vars"
}

# Test 9: Mixed content with vars
test_mixed_content() {
    export USER="${USER:-testuser}"
    local result
    result=$(safe_expand_vars 'Hello ${USER}, your home is ${HOME}')
    assert_equals "Hello $USER, your home is $HOME" "$result" "Should expand vars in mixed content"
}

# Test 10: Literal dollar sign in path (no variable pattern)
test_literal_dollar() {
    local result
    result=$(safe_expand_vars '/path/to/$file.txt')
    # $file is treated as a variable and expanded to empty since it's undefined
    assert_equals "/path/to/.txt" "$result" "Should expand undefined \$var to empty"
}

# Test 11: Expand ${VAR:-default} with unset var
test_default_value_unset() {
    unset XDG_CONFIG_HOME 2>/dev/null || true
    local result
    result=$(safe_expand_vars '${XDG_CONFIG_HOME:-$HOME/.config}/nvim')
    assert_equals "$HOME/.config/nvim" "$result" "Should use default when var unset"
}

# Test 12: Expand ${VAR:-default} with set var
test_default_value_set() {
    export XDG_CONFIG_HOME="/custom/config"
    local result
    result=$(safe_expand_vars '${XDG_CONFIG_HOME:-$HOME/.config}/nvim')
    assert_equals "/custom/config/nvim" "$result" "Should use var value when set"
    unset XDG_CONFIG_HOME
}

# Run all tests
test_expand_home_braces
test_expand_home_no_braces
test_block_command_substitution
test_block_backtick_injection
test_block_dangerous_rm
test_expand_multiple_vars
test_undefined_var
test_no_expansion
test_mixed_content
test_literal_dollar
test_default_value_unset
test_default_value_set

print_summary
