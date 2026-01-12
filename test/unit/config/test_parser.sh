#!/usr/bin/env bash
# test/unit/config/test_parser.sh
# Unit tests for config/parser.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source fs module first (for mock support)
source "$SCRIPT_DIR/../../../lib/core/fs.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/config/parser.sh"

echo "Testing: config/parser"
echo ""

# ============================================================================
# Setup
# ============================================================================

setup() {
    fs_init "mock"
    fs_mock_reset
}

# ============================================================================
# config_parse_line Tests
# ============================================================================

test_parse_line_simple_double_quoted() {
    setup
    local key value

    config_parse_line 'target="/home/user/.gitconfig"' key value
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for valid line"
    assert_equals "target" "$key" "key should be 'target'"
    assert_equals "/home/user/.gitconfig" "$value" "value should be unquoted path"
}

test_parse_line_simple_single_quoted() {
    setup
    local key value

    config_parse_line "merge_hook='builtin:symlink'" key value
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for valid line"
    assert_equals "merge_hook" "$key" "key should be 'merge_hook'"
    assert_equals "builtin:symlink" "$value" "value should be unquoted"
}

test_parse_line_unquoted() {
    setup
    local key value

    config_parse_line "debug=true" key value
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for valid line"
    assert_equals "debug" "$key" "key should be 'debug'"
    assert_equals "true" "$value" "value should be 'true'"
}

test_parse_line_with_env_var() {
    setup
    local key value
    export HOME="/home/testuser"

    config_parse_line 'target="${HOME}/.gitconfig"' key value

    assert_equals "/home/testuser/.gitconfig" "$value" "HOME should be expanded"
}

test_parse_line_with_dollar_var() {
    setup
    local key value
    export HOME="/home/testuser"

    config_parse_line 'target="$HOME/.zshrc"' key value

    assert_equals "/home/testuser/.zshrc" "$value" "HOME should be expanded"
}

test_parse_line_with_inline_comment() {
    setup
    local key value

    config_parse_line 'target="/home/user/.config"  # This is a comment' key value

    assert_equals "target" "$key" "key should be 'target'"
    assert_equals "/home/user/.config" "$value" "inline comment should be stripped"
}

test_parse_line_skip_empty() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line "" key value || rc=$?

    assert_equals "1" "$rc" "should return 1 for empty line"
}

test_parse_line_skip_whitespace_only() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line "   " key value || rc=$?

    assert_equals "1" "$rc" "should return 1 for whitespace-only line"
}

test_parse_line_skip_comment() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line "# This is a comment" key value || rc=$?

    assert_equals "1" "$rc" "should return 1 for comment line"
}

test_parse_line_skip_comment_with_spaces() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line "  # Indented comment" key value || rc=$?

    assert_equals "1" "$rc" "should return 1 for indented comment"
}

test_parse_line_invalid_no_equals() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line "this has no equals sign" key value || rc=$?

    assert_equals "2" "$rc" "should return 2 for line without ="
}

test_parse_line_invalid_empty_key() {
    setup
    local key="" value=""

    local rc=0
    config_parse_line '="value"' key value || rc=$?

    assert_equals "2" "$rc" "should return 2 for empty key"
}

test_parse_line_with_whitespace_around_equals() {
    setup
    local key value

    config_parse_line '  target  =  "/home/user/.config"  ' key value

    assert_equals "target" "$key" "whitespace around key should be trimmed"
    assert_equals "/home/user/.config" "$value" "value should be parsed correctly"
}

test_parse_line_underscore_in_key() {
    setup
    local key value

    config_parse_line 'layers_base="local:configs/git"' key value

    assert_equals "layers_base" "$key" "key with underscore should work"
    assert_equals "local:configs/git" "$value" "value should be parsed"
}

# ============================================================================
# config_expand_vars Tests
# ============================================================================

test_expand_vars_braced() {
    export TEST_VAR="hello"

    local result
    result=$(config_expand_vars '${TEST_VAR}/world')

    assert_equals "hello/world" "$result" "braced var should be expanded"
}

test_expand_vars_unbraced() {
    export TEST_VAR="hello"

    local result
    result=$(config_expand_vars '$TEST_VAR/world')

    assert_equals "hello/world" "$result" "unbraced var should be expanded"
}

test_expand_vars_multiple() {
    export USER="alice"
    export HOME="/home/alice"

    local result
    result=$(config_expand_vars '${HOME}/${USER}/.config')

    assert_equals "/home/alice/alice/.config" "$result" "multiple vars should expand"
}

test_expand_vars_undefined() {
    unset UNDEFINED_VAR 2>/dev/null || true

    local result
    result=$(config_expand_vars '${UNDEFINED_VAR}/path')

    assert_equals "/path" "$result" "undefined var should expand to empty"
}

test_expand_vars_no_vars() {
    local result
    result=$(config_expand_vars '/absolute/path/no/vars')

    assert_equals "/absolute/path/no/vars" "$result" "string without vars unchanged"
}

# ============================================================================
# config_parse_tool_conf Tests
# ============================================================================

test_parse_tool_conf_basic() {
    setup
    fs_mock_set "/tools/git/tool.conf" 'target="/home/user/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"'

    declare -A result
    config_parse_tool_conf "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "/home/user/.gitconfig" "${result[target]}" "target should be set"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook should be set"
    assert_equals "local:configs/git" "${result[layers_base]}" "layers_base should be set"
}

test_parse_tool_conf_with_comments() {
    setup
    fs_mock_set "/tools/git/tool.conf" '# Comment at start
target="/home/user/.gitconfig"  # Inline comment
# Another comment
merge_hook="builtin:symlink"'

    declare -A result
    config_parse_tool_conf "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "/home/user/.gitconfig" "${result[target]}" "target should be set"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook should be set"
}

test_parse_tool_conf_multiple_layers() {
    setup
    fs_mock_set "/tools/git/tool.conf" 'target="~/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
layers_stripe="STRIPE_DOTFILES:git"
layers_personal="local:personal/git"'

    declare -A result
    config_parse_tool_conf "/tools/git" result

    assert_equals "local:configs/git" "${result[layers_base]}" "layers_base"
    assert_equals "STRIPE_DOTFILES:git" "${result[layers_stripe]}" "layers_stripe"
    assert_equals "local:personal/git" "${result[layers_personal]}" "layers_personal"
}

test_parse_tool_conf_with_install_hook() {
    setup
    fs_mock_set "/tools/git/tool.conf" 'target="~/.gitconfig"
merge_hook="./merge.sh"
install_hook="./install.sh"'

    declare -A result
    config_parse_tool_conf "/tools/git" result

    assert_equals "./merge.sh" "${result[merge_hook]}" "merge_hook should be relative path"
    assert_equals "./install.sh" "${result[install_hook]}" "install_hook should be set"
}

test_parse_tool_conf_not_found() {
    setup
    # No mock file set

    declare -A result
    local rc=0
    config_parse_tool_conf "/tools/nonexistent" result || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND"
}

test_parse_tool_conf_empty_file() {
    setup
    fs_mock_set "/tools/empty/tool.conf" ""

    declare -A result
    config_parse_tool_conf "/tools/empty" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "empty file should be valid (returns E_OK)"
}

test_parse_tool_conf_env_expansion() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/git/tool.conf" 'target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"'

    declare -A result
    config_parse_tool_conf "/tools/git" result

    assert_equals "/home/testuser/.gitconfig" "${result[target]}" "HOME should be expanded"
}

# ============================================================================
# Run Tests
# ============================================================================

# Line parsing tests
test_parse_line_simple_double_quoted
test_parse_line_simple_single_quoted
test_parse_line_unquoted
test_parse_line_with_env_var
test_parse_line_with_dollar_var
test_parse_line_with_inline_comment
test_parse_line_skip_empty
test_parse_line_skip_whitespace_only
test_parse_line_skip_comment
test_parse_line_skip_comment_with_spaces
test_parse_line_invalid_no_equals
test_parse_line_invalid_empty_key
test_parse_line_with_whitespace_around_equals
test_parse_line_underscore_in_key

# Variable expansion tests
test_expand_vars_braced
test_expand_vars_unbraced
test_expand_vars_multiple
test_expand_vars_undefined
test_expand_vars_no_vars

# Full config parsing tests
test_parse_tool_conf_basic
test_parse_tool_conf_with_comments
test_parse_tool_conf_multiple_layers
test_parse_tool_conf_with_install_hook
test_parse_tool_conf_not_found
test_parse_tool_conf_empty_file
test_parse_tool_conf_env_expansion

# ============================================================================
# _config_parse_tool_json Tests
# ============================================================================

test_parse_tool_json_basic() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/git/tool.json" '{
  "target": "~/.gitconfig",
  "merge_hook": "builtin:symlink",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" }
  ]
}'

    declare -A result
    _config_parse_tool_json "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK for valid JSON"
    assert_equals "/home/testuser/.gitconfig" "${result[target]}" "target should expand ~"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook should be set"
    assert_equals "local:configs/git" "${result[layers_base]}" "layers_base should be set"
}

test_parse_tool_json_multiple_layers() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/git/tool.json" '{
  "target": "~/.gitconfig",
  "merge_hook": "./merge.sh",
  "install_hook": "./install.sh",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" },
    { "name": "stripe", "source": "STRIPE_DOTFILES", "path": "git" },
    { "name": "personal", "source": "local", "path": "personal/git" }
  ]
}'

    declare -A result
    _config_parse_tool_json "/tools/git" result

    assert_equals "./merge.sh" "${result[merge_hook]}" "merge_hook should be script path"
    assert_equals "./install.sh" "${result[install_hook]}" "install_hook should be set"
    assert_equals "local:configs/git" "${result[layers_base]}" "layers_base"
    assert_equals "STRIPE_DOTFILES:git" "${result[layers_stripe]}" "layers_stripe"
    assert_equals "local:personal/git" "${result[layers_personal]}" "layers_personal"
}

test_parse_tool_json_not_found() {
    setup
    # No mock file set

    declare -A result
    local rc=0
    _config_parse_tool_json "/tools/nonexistent" result || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND when no JSON file"
}

test_parse_tool_json_invalid_json() {
    setup
    fs_mock_set "/tools/broken/tool.json" '{ invalid json }'

    declare -A result
    local rc=0
    _config_parse_tool_json "/tools/broken" result 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "should return E_VALIDATION for invalid JSON"
}

test_parse_tool_json_missing_fields() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/minimal/tool.json" '{
  "target": "~/.config/tool",
  "layers": []
}'

    declare -A result
    _config_parse_tool_json "/tools/minimal" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK even with missing optional fields"
    assert_equals "/home/testuser/.config/tool" "${result[target]}" "target should be set"
    assert_equals "" "${result[merge_hook]:-}" "merge_hook should be empty"
    assert_equals "" "${result[install_hook]:-}" "install_hook should be empty"
}

# ============================================================================
# config_parse_tool Tests (JSON preferred over conf)
# ============================================================================

test_parse_tool_prefers_json() {
    setup
    export HOME="/home/testuser"
    # Set up both JSON and conf files
    fs_mock_set "/tools/git/tool.json" '{
  "target": "~/.gitconfig-json",
  "merge_hook": "builtin:symlink",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" }
  ]
}'
    fs_mock_set "/tools/git/tool.conf" 'target="/home/testuser/.gitconfig-conf"
merge_hook="builtin:concat"
layers_base="local:old/path"'

    declare -A result
    config_parse_tool "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "/home/testuser/.gitconfig-json" "${result[target]}" "JSON should be preferred over conf"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook from JSON"
}

test_parse_tool_falls_back_to_conf() {
    setup
    export HOME="/home/testuser"
    # Only conf file, no JSON
    fs_mock_set "/tools/git/tool.conf" 'target="/home/testuser/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"'

    declare -A result
    config_parse_tool "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "/home/testuser/.gitconfig" "${result[target]}" "should use conf when no JSON"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook from conf"
}

test_parse_tool_not_found() {
    setup
    # No JSON or conf file

    declare -A result
    local rc=0
    config_parse_tool "/tools/nonexistent" result || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND when neither exists"
}

# JSON parsing tests
test_parse_tool_json_basic
test_parse_tool_json_multiple_layers
test_parse_tool_json_not_found
test_parse_tool_json_invalid_json
test_parse_tool_json_missing_fields

# config_parse_tool tests (JSON preferred)
test_parse_tool_prefers_json
test_parse_tool_falls_back_to_conf
test_parse_tool_not_found

print_summary
