#!/usr/bin/env bash
# test/unit/config/test_parser.sh
# Unit tests for config/parser.sh (JSON parsing only)

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

test_parse_tool_json_empty_layers() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/empty/tool.json" '{
  "target": "~/.config/empty",
  "merge_hook": "builtin:symlink",
  "layers": []
}'

    declare -A result
    _config_parse_tool_json "/tools/empty" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK with empty layers array"
    assert_equals "/home/testuser/.config/empty" "${result[target]}" "target should be set"
}

# ============================================================================
# config_parse_tool Tests
# ============================================================================

test_parse_tool_json_only() {
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
    config_parse_tool "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "/home/testuser/.gitconfig" "${result[target]}" "target should be set from JSON"
    assert_equals "builtin:symlink" "${result[merge_hook]}" "merge_hook from JSON"
}

test_parse_tool_not_found() {
    setup
    # No JSON file

    declare -A result
    local rc=0
    config_parse_tool "/tools/nonexistent" result || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "should return E_NOT_FOUND when no JSON exists"
}

test_parse_tool_with_schema_field() {
    setup
    export HOME="/home/testuser"
    fs_mock_set "/tools/git/tool.json" '{
  "$schema": "../../lib/dotfiles-system/schemas/tool.schema.json",
  "target": "~/.gitconfig",
  "merge_hook": "builtin:symlink",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" }
  ]
}'

    declare -A result
    config_parse_tool "/tools/git" result
    local rc=$?

    assert_equals "$E_OK" "$rc" "should ignore $schema field and parse successfully"
    assert_equals "/home/testuser/.gitconfig" "${result[target]}" "target should be set"
}

# ============================================================================
# Run Tests
# ============================================================================

# JSON parsing tests
test_parse_tool_json_basic
test_parse_tool_json_multiple_layers
test_parse_tool_json_not_found
test_parse_tool_json_invalid_json
test_parse_tool_json_missing_fields
test_parse_tool_json_empty_layers

# config_parse_tool tests
test_parse_tool_json_only
test_parse_tool_not_found
test_parse_tool_with_schema_field

print_summary
