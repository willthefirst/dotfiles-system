#!/usr/bin/env bash
# test/unit/resolver/test_layers.sh
# Unit tests for resolver/layers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source fs module first (for mock support)
source "$SCRIPT_DIR/../../../lib/core/fs.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/resolver/layers.sh"

echo "Testing: resolver/layers"
echo ""

# ============================================================================
# Setup
# ============================================================================

setup() {
    fs_init "mock"
    fs_mock_reset
    repos_mock_reset
    export HOME="/home/testuser"
}

# ============================================================================
# layer_resolver_init Tests
# ============================================================================

test_resolver_init_basic() {
    setup

    layer_resolver_init "/path/to/dotfiles"
    local rc=$?

    assert_equals "$E_OK" "$rc" "init should succeed"

    local dir
    dir=$(layer_get_dotfiles_dir)
    assert_equals "/path/to/dotfiles" "$dir" "dotfiles dir stored"
}

test_resolver_init_with_tilde() {
    setup

    layer_resolver_init "~/.dotfiles"
    local rc=$?

    assert_equals "$E_OK" "$rc" "init with ~ should succeed"

    local dir
    dir=$(layer_get_dotfiles_dir)
    assert_equals "/home/testuser/.dotfiles" "$dir" "tilde expanded"
}

test_resolver_init_empty() {
    setup

    local rc=0
    layer_resolver_init "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty dir returns error"
}

test_resolver_init_loads_repos() {
    setup

    fs_mock_set "/dotfiles/repos.conf" 'WORK_REPO="git@example.com:work.git|/path/to/work"'

    layer_resolver_init "/dotfiles"

    repos_is_configured "WORK_REPO"
    local rc=$?

    assert_equals "0" "$rc" "repo loaded from repos.conf"
}

# ============================================================================
# layer_parse_spec Tests
# ============================================================================

test_parse_spec_local() {
    setup
    local source path

    layer_parse_spec "local:configs/git" source path
    local rc=$?

    assert_equals "$E_OK" "$rc" "parse should succeed"
    assert_equals "local" "$source" "source is 'local'"
    assert_equals "configs/git" "$path" "path parsed"
}

test_parse_spec_repo() {
    setup
    local source path

    layer_parse_spec "STRIPE_DOTFILES:git/config" source path
    local rc=$?

    assert_equals "$E_OK" "$rc" "parse should succeed"
    assert_equals "STRIPE_DOTFILES" "$source" "source is repo name"
    assert_equals "git/config" "$path" "path parsed"
}

test_parse_spec_nested_path() {
    setup
    local source path

    layer_parse_spec "local:deeply/nested/path/to/config" source path
    local rc=$?

    assert_equals "$E_OK" "$rc" "parse should succeed"
    assert_equals "deeply/nested/path/to/config" "$path" "nested path preserved"
}

test_parse_spec_empty() {
    setup
    local source="" path=""

    local rc=0
    layer_parse_spec "" source path || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty spec returns error"
}

test_parse_spec_no_colon() {
    setup
    local source="" path=""

    local rc=0
    layer_parse_spec "invalid_no_colon" source path || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "spec without colon returns error"
}

test_parse_spec_empty_source() {
    setup
    local source="" path=""

    local rc=0
    layer_parse_spec ":path/only" source path || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty source returns error"
}

test_parse_spec_empty_path() {
    setup
    local source="" path=""

    local rc=0
    layer_parse_spec "source:" source path || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty path returns error"
}

# ============================================================================
# layer_resolve_spec Tests
# ============================================================================

test_resolve_spec_local() {
    setup
    layer_resolver_init "/path/to/dotfiles"

    local result
    result=$(layer_resolve_spec "local:configs/git")
    local rc=$?

    assert_equals "$E_OK" "$rc" "resolve should succeed"
    assert_equals "/path/to/dotfiles/configs/git" "$result" "local path resolved"
}

test_resolve_spec_local_nested() {
    setup
    layer_resolver_init "/dotfiles"

    local result
    result=$(layer_resolve_spec "local:tools/nvim/configs")

    assert_equals "/dotfiles/tools/nvim/configs" "$result" "nested local path resolved"
}

test_resolve_spec_external_repo() {
    setup
    layer_resolver_init "/dotfiles"
    repos_mock_set "WORK_DOTFILES" "git@example.com:work.git" "/work/dotfiles"

    local result
    result=$(layer_resolve_spec "WORK_DOTFILES:git")
    local rc=$?

    assert_equals "$E_OK" "$rc" "resolve should succeed"
    assert_equals "/work/dotfiles/git" "$result" "external repo path resolved"
}

test_resolve_spec_unknown_repo() {
    setup
    layer_resolver_init "/dotfiles"

    local rc=0
    layer_resolve_spec "UNKNOWN_REPO:path" 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "unknown repo returns E_NOT_FOUND"
}

test_resolve_spec_empty() {
    setup
    layer_resolver_init "/dotfiles"

    local rc=0
    layer_resolve_spec "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty spec returns error"
}

test_resolve_spec_normalizes_path() {
    setup
    layer_resolver_init "/dotfiles"

    local result
    result=$(layer_resolve_spec "local:configs//git/./")

    assert_equals "/dotfiles/configs/git" "$result" "path normalized"
}

# ============================================================================
# layer_resolve_tool_config Tests
# ============================================================================

test_resolve_tool_config_single_layer() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    layer_resolve_tool_config config
    local rc=$?

    assert_equals "$E_OK" "$rc" "resolve should succeed"

    local resolved
    resolved=$(tool_config_get_layer_resolved config 0)
    assert_equals "/dotfiles/configs/git" "$resolved" "layer resolved"
}

test_resolve_tool_config_multiple_layers() {
    setup
    layer_resolver_init "/dotfiles"
    repos_mock_set "WORK_DOTFILES" "git@example.com:work.git" "/work/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_add_layer config "work" "WORK_DOTFILES" "git"

    layer_resolve_tool_config config
    local rc=$?

    assert_equals "$E_OK" "$rc" "resolve should succeed"

    local resolved_base resolved_work
    resolved_base=$(tool_config_get_layer_resolved config 0)
    resolved_work=$(tool_config_get_layer_resolved config 1)

    assert_equals "/dotfiles/configs/git" "$resolved_base" "base layer resolved"
    assert_equals "/work/dotfiles/git" "$resolved_work" "work layer resolved"
}

test_resolve_tool_config_no_layers() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"

    layer_resolve_tool_config config
    local rc=$?

    assert_equals "$E_OK" "$rc" "resolve with no layers succeeds"
}

test_resolve_tool_config_unknown_repo() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "work" "UNKNOWN_REPO" "git"

    local rc=0
    layer_resolve_tool_config config 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "unknown repo in layer returns E_NOT_FOUND"
}

# ============================================================================
# layer_validate_resolved Tests
# ============================================================================

test_validate_resolved_all_exist() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    # Resolve first
    layer_resolve_tool_config config

    # Set up the directory in mock filesystem
    fs_mock_set_dir "/dotfiles/configs/git"

    layer_validate_resolved config
    local rc=$?

    assert_equals "$E_OK" "$rc" "validation passes when all exist"
}

test_validate_resolved_missing_dir() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    # Resolve first
    layer_resolve_tool_config config

    # Don't create the directory - it should be missing

    local rc=0
    layer_validate_resolved config 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "validation fails when dir missing"
}

test_validate_resolved_not_resolved() {
    setup

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    # Don't resolve - resolved_path will be empty

    local rc=0
    layer_validate_resolved config 2>/dev/null || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "validation fails when not resolved"
}

# ============================================================================
# layer_get_resolved_paths Tests
# ============================================================================

test_get_resolved_paths_single() {
    setup
    layer_resolver_init "/dotfiles"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"

    layer_resolve_tool_config config

    local paths
    paths=$(layer_get_resolved_paths config)

    assert_equals "/dotfiles/configs/git" "$paths" "single path returned"
}

test_get_resolved_paths_multiple() {
    setup
    layer_resolver_init "/dotfiles"
    repos_mock_set "WORK" "git@example.com:work.git" "/work"

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
    tool_config_add_layer config "base" "local" "configs/git"
    tool_config_add_layer config "work" "WORK" "git"

    layer_resolve_tool_config config

    local paths
    paths=$(layer_get_resolved_paths config)

    assert_equals "/dotfiles/configs/git:/work/git" "$paths" "colon-separated paths"
}

test_get_resolved_paths_empty() {
    setup

    declare -A config
    tool_config_new config "git" "~/.gitconfig" "builtin:symlink"

    local paths
    paths=$(layer_get_resolved_paths config)

    assert_equals "" "$paths" "empty when no layers"
}

# ============================================================================
# Run Tests
# ============================================================================

# layer_resolver_init tests
test_resolver_init_basic
test_resolver_init_with_tilde
test_resolver_init_empty
test_resolver_init_loads_repos

# layer_parse_spec tests
test_parse_spec_local
test_parse_spec_repo
test_parse_spec_nested_path
test_parse_spec_empty
test_parse_spec_no_colon
test_parse_spec_empty_source
test_parse_spec_empty_path

# layer_resolve_spec tests
test_resolve_spec_local
test_resolve_spec_local_nested
test_resolve_spec_external_repo
test_resolve_spec_unknown_repo
test_resolve_spec_empty
test_resolve_spec_normalizes_path

# layer_resolve_tool_config tests
test_resolve_tool_config_single_layer
test_resolve_tool_config_multiple_layers
test_resolve_tool_config_no_layers
test_resolve_tool_config_unknown_repo

# layer_validate_resolved tests
test_validate_resolved_all_exist
test_validate_resolved_missing_dir
test_validate_resolved_not_resolved

# layer_get_resolved_paths tests
test_get_resolved_paths_single
test_get_resolved_paths_multiple
test_get_resolved_paths_empty

print_summary
