#!/usr/bin/env bash
# test/unit/resolver/test_paths.sh
# Unit tests for resolver/paths.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/resolver/paths.sh"

echo "Testing: resolver/paths"
echo ""

# ============================================================================
# path_expand_tilde Tests
# ============================================================================

test_expand_tilde_home() {
    export HOME="/home/testuser"

    local result
    result=$(path_expand_tilde "~")

    assert_equals "/home/testuser" "$result" "~ should expand to HOME"
}

test_expand_tilde_path() {
    export HOME="/home/testuser"

    local result
    result=$(path_expand_tilde "~/.config")

    assert_equals "/home/testuser/.config" "$result" "~/ should expand to HOME/"
}

test_expand_tilde_nested() {
    export HOME="/home/testuser"

    local result
    result=$(path_expand_tilde "~/.config/nvim")

    assert_equals "/home/testuser/.config/nvim" "$result" "nested path after ~ should work"
}

test_expand_tilde_no_tilde() {
    local result
    result=$(path_expand_tilde "/absolute/path")

    assert_equals "/absolute/path" "$result" "path without ~ unchanged"
}

test_expand_tilde_tilde_in_middle() {
    local result
    result=$(path_expand_tilde "/path/with/~/middle")

    assert_equals "/path/with/~/middle" "$result" "~ in middle should not expand"
}

test_expand_tilde_empty_returns_error() {
    local rc=0
    path_expand_tilde "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty path should return E_INVALID_INPUT"
}

# ============================================================================
# path_expand_env_vars Tests
# ============================================================================

test_expand_env_vars_braced() {
    export TEST_VAR="myvalue"

    local result
    result=$(path_expand_env_vars '${TEST_VAR}/path')

    assert_equals "myvalue/path" "$result" "braced var should expand"
}

test_expand_env_vars_unbraced() {
    export TEST_VAR="myvalue"

    local result
    result=$(path_expand_env_vars '$TEST_VAR/path')

    assert_equals "myvalue/path" "$result" "unbraced var should expand"
}

test_expand_env_vars_multiple() {
    export USER="alice"
    export CONFIG_DIR="config"

    local result
    result=$(path_expand_env_vars '${HOME}/${USER}/${CONFIG_DIR}')

    assert_contains "$result" "alice" "USER should be expanded"
    assert_contains "$result" "config" "CONFIG_DIR should be expanded"
}

test_expand_env_vars_undefined() {
    unset UNDEFINED_VAR_12345 2>/dev/null || true

    local result
    result=$(path_expand_env_vars '${UNDEFINED_VAR_12345}/path')

    assert_equals "/path" "$result" "undefined var should become empty"
}

test_expand_env_vars_no_vars() {
    local result
    result=$(path_expand_env_vars '/plain/path')

    assert_equals "/plain/path" "$result" "path without vars unchanged"
}

test_expand_env_vars_empty_returns_error() {
    local rc=0
    path_expand_env_vars "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty path should return E_INVALID_INPUT"
}

test_expand_env_vars_end_of_string() {
    export MYVAR="value"

    local result
    result=$(path_expand_env_vars '/path/$MYVAR')

    assert_equals "/path/value" "$result" "var at end of string should expand"
}

# ============================================================================
# path_expand Tests (combined tilde + env vars)
# ============================================================================

test_expand_full() {
    export HOME="/home/testuser"
    export SUBDIR="configs"

    local result
    result=$(path_expand '~/${SUBDIR}/app')

    assert_equals "/home/testuser/configs/app" "$result" "full expansion should work"
}

test_expand_only_tilde() {
    export HOME="/home/testuser"

    local result
    result=$(path_expand "~/.config")

    assert_equals "/home/testuser/.config" "$result" "tilde-only should work"
}

test_expand_only_env() {
    export MYPATH="/some/path"

    local result
    result=$(path_expand '${MYPATH}/sub')

    assert_equals "/some/path/sub" "$result" "env-only should work"
}

# ============================================================================
# path_resolve_relative Tests
# ============================================================================

test_resolve_relative_basic() {
    local result
    result=$(path_resolve_relative "configs/git" "/path/to/dotfiles")

    assert_equals "/path/to/dotfiles/configs/git" "$result" "basic relative path"
}

test_resolve_relative_already_absolute() {
    local result
    result=$(path_resolve_relative "/absolute/path" "/base")

    assert_equals "/absolute/path" "$result" "absolute path unchanged"
}

test_resolve_relative_base_trailing_slash() {
    local result
    result=$(path_resolve_relative "subdir" "/base/")

    assert_equals "/base/subdir" "$result" "trailing slash on base handled"
}

test_resolve_relative_empty_path_error() {
    local rc=0
    path_resolve_relative "" "/base" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty path returns error"
}

test_resolve_relative_empty_base_error() {
    local rc=0
    path_resolve_relative "path" "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty base returns error"
}

# ============================================================================
# path_is_absolute Tests
# ============================================================================

test_is_absolute_root() {
    path_is_absolute "/"
    local rc=$?

    assert_equals "0" "$rc" "/ is absolute"
}

test_is_absolute_path() {
    path_is_absolute "/home/user"
    local rc=$?

    assert_equals "0" "$rc" "/home/user is absolute"
}

test_is_absolute_tilde() {
    path_is_absolute "~/.config"
    local rc=$?

    assert_equals "0" "$rc" "~ path is considered absolute"
}

test_is_absolute_relative() {
    local rc=0
    path_is_absolute "relative/path" || rc=$?

    assert_equals "1" "$rc" "relative path returns 1"
}

test_is_absolute_empty() {
    local rc=0
    path_is_absolute "" || rc=$?

    assert_equals "1" "$rc" "empty path returns 1"
}

# ============================================================================
# path_normalize Tests
# ============================================================================

test_normalize_double_slash() {
    local result
    result=$(path_normalize "/path//to///file")

    assert_equals "/path/to/file" "$result" "double slashes removed"
}

test_normalize_trailing_slash() {
    local result
    result=$(path_normalize "/path/to/dir/")

    assert_equals "/path/to/dir" "$result" "trailing slash removed"
}

test_normalize_dot() {
    local result
    result=$(path_normalize "/path/./to/./file")

    assert_equals "/path/to/file" "$result" "single dots removed"
}

test_normalize_dotdot() {
    local result
    result=$(path_normalize "/path/to/foo/../file")

    assert_equals "/path/to/file" "$result" ".. resolved"
}

test_normalize_root() {
    local result
    result=$(path_normalize "/")

    assert_equals "/" "$result" "root unchanged"
}

test_normalize_relative() {
    local result
    result=$(path_normalize "relative/./path")

    assert_equals "relative/path" "$result" "relative path normalized"
}

test_normalize_relative_dotdot() {
    local result
    result=$(path_normalize "foo/bar/../baz")

    assert_equals "foo/baz" "$result" "relative .. resolved"
}

test_normalize_leading_dotdot() {
    local result
    result=$(path_normalize "../relative/path")

    assert_equals "../relative/path" "$result" "leading .. preserved for relative"
}

test_normalize_empty_returns_error() {
    local rc=0
    path_normalize "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty returns error"
}

# ============================================================================
# path_join Tests
# ============================================================================

test_join_basic() {
    local result
    result=$(path_join "/base" "relative/path")

    assert_equals "/base/relative/path" "$result" "basic join"
}

test_join_absolute_path() {
    local result
    result=$(path_join "/base" "/absolute/path")

    assert_equals "/absolute/path" "$result" "absolute path overrides base"
}

test_join_empty_base() {
    local result
    result=$(path_join "" "relative/path")

    assert_equals "relative/path" "$result" "empty base returns path"
}

test_join_empty_path() {
    local result
    result=$(path_join "/base" "")

    assert_equals "/base" "$result" "empty path returns base"
}

test_join_both_empty() {
    local result
    result=$(path_join "" "")

    assert_equals "" "$result" "both empty returns empty"
}

test_join_base_trailing_slash() {
    local result
    result=$(path_join "/base/" "relative")

    assert_equals "/base/relative" "$result" "trailing slash handled"
}

# ============================================================================
# Run Tests
# ============================================================================

# path_expand_tilde tests
test_expand_tilde_home
test_expand_tilde_path
test_expand_tilde_nested
test_expand_tilde_no_tilde
test_expand_tilde_tilde_in_middle
test_expand_tilde_empty_returns_error

# path_expand_env_vars tests
test_expand_env_vars_braced
test_expand_env_vars_unbraced
test_expand_env_vars_multiple
test_expand_env_vars_undefined
test_expand_env_vars_no_vars
test_expand_env_vars_empty_returns_error
test_expand_env_vars_end_of_string

# path_expand tests
test_expand_full
test_expand_only_tilde
test_expand_only_env

# path_resolve_relative tests
test_resolve_relative_basic
test_resolve_relative_already_absolute
test_resolve_relative_base_trailing_slash
test_resolve_relative_empty_path_error
test_resolve_relative_empty_base_error

# path_is_absolute tests
test_is_absolute_root
test_is_absolute_path
test_is_absolute_tilde
test_is_absolute_relative
test_is_absolute_empty

# path_normalize tests
test_normalize_double_slash
test_normalize_trailing_slash
test_normalize_dot
test_normalize_dotdot
test_normalize_root
test_normalize_relative
test_normalize_relative_dotdot
test_normalize_leading_dotdot
test_normalize_empty_returns_error

# path_join tests
test_join_basic
test_join_absolute_path
test_join_empty_base
test_join_empty_path
test_join_both_empty
test_join_base_trailing_slash

print_summary
