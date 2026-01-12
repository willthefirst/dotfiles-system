#!/usr/bin/env bash
# test/unit/resolver/test_repos.sh
# Unit tests for resolver/repos.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Source fs module first (for mock support)
source "$SCRIPT_DIR/../../../lib/core/fs.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/resolver/repos.sh"

echo "Testing: resolver/repos"
echo ""

# ============================================================================
# Setup
# ============================================================================

setup() {
    fs_init "mock"
    fs_mock_reset
    repos_mock_reset
}

# ============================================================================
# repos_init Tests
# ============================================================================

test_repos_init_basic() {
    setup
    export HOME="/home/testuser"

    fs_mock_set "/dotfiles/repos.conf" 'STRIPE_DOTFILES="git@github.com:stripe/dotfiles.git|${HOME}/work/stripe-dotfiles"
WORK_DOTFILES="git@github.com:company/dotfiles.git|/opt/work/dotfiles"'

    repos_init "/dotfiles"
    local rc=$?

    assert_equals "$E_OK" "$rc" "init should succeed"

    local path
    path=$(repos_get_path "STRIPE_DOTFILES")
    assert_equals "/home/testuser/work/stripe-dotfiles" "$path" "STRIPE_DOTFILES path resolved"

    path=$(repos_get_path "WORK_DOTFILES")
    assert_equals "/opt/work/dotfiles" "$path" "WORK_DOTFILES path resolved"
}

test_repos_init_empty_dir() {
    setup

    local rc=0
    repos_init "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty dir returns error"
}

test_repos_init_missing_repos_conf() {
    setup
    # No repos.conf file

    repos_init "/dotfiles"
    local rc=$?

    assert_equals "$E_OK" "$rc" "missing repos.conf is OK (optional)"
}

test_repos_init_with_comments() {
    setup

    fs_mock_set "/dotfiles/repos.conf" '# This is a comment
REPO_A="git@example.com:a.git|/path/to/a"
# Another comment
REPO_B="git@example.com:b.git|/path/to/b"'

    repos_init "/dotfiles"

    local path_a path_b
    path_a=$(repos_get_path "REPO_A")
    path_b=$(repos_get_path "REPO_B")

    assert_equals "/path/to/a" "$path_a" "REPO_A parsed"
    assert_equals "/path/to/b" "$path_b" "REPO_B parsed"
}

test_repos_init_env_expansion() {
    setup
    export REPOS_BASE="/custom/repos"

    fs_mock_set "/dotfiles/repos.conf" 'MY_REPO="git@example.com:repo.git|${REPOS_BASE}/myrepo"'

    repos_init "/dotfiles"

    local path
    path=$(repos_get_path "MY_REPO")

    assert_equals "/custom/repos/myrepo" "$path" "env var expanded in path"
}

# ============================================================================
# repos_get_path Tests
# ============================================================================

test_get_path_exists() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"

    local path
    path=$(repos_get_path "TEST_REPO")
    local rc=$?

    assert_equals "$E_OK" "$rc" "should succeed"
    assert_equals "/path/to/test" "$path" "path returned"
}

test_get_path_not_configured() {
    setup

    local rc=0
    repos_get_path "NONEXISTENT_REPO" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "unknown repo returns E_NOT_FOUND"
}

test_get_path_empty_name() {
    setup

    local rc=0
    repos_get_path "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty name returns E_INVALID_INPUT"
}

# ============================================================================
# repos_get_url Tests
# ============================================================================

test_get_url_exists() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"

    local url
    url=$(repos_get_url "TEST_REPO")
    local rc=$?

    assert_equals "$E_OK" "$rc" "should succeed"
    assert_equals "git@example.com:test.git" "$url" "url returned"
}

test_get_url_not_configured() {
    setup

    local rc=0
    repos_get_url "NONEXISTENT_REPO" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "unknown repo returns E_NOT_FOUND"
}

# ============================================================================
# repos_is_configured Tests
# ============================================================================

test_is_configured_true() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"

    repos_is_configured "TEST_REPO"
    local rc=$?

    assert_equals "0" "$rc" "configured repo returns 0"
}

test_is_configured_false() {
    setup

    local rc=0
    repos_is_configured "NONEXISTENT_REPO" || rc=$?

    assert_equals "1" "$rc" "unknown repo returns 1"
}

test_is_configured_empty() {
    setup

    local rc=0
    repos_is_configured "" || rc=$?

    assert_equals "1" "$rc" "empty name returns 1"
}

# ============================================================================
# repos_exists Tests
# ============================================================================

test_exists_true() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 1

    repos_exists "TEST_REPO"
    local rc=$?

    assert_equals "0" "$rc" "existing repo returns 0"
}

test_exists_false() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 0

    local rc=0
    repos_exists "TEST_REPO" || rc=$?

    assert_equals "1" "$rc" "non-existing repo returns 1"
}

test_exists_not_configured() {
    setup

    local rc=0
    repos_exists "NONEXISTENT_REPO" || rc=$?

    assert_equals "1" "$rc" "unconfigured repo returns 1"
}

test_exists_with_fs_mock() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    # Set up mock .git directory
    fs_mock_set_dir "/path/to/test/.git"

    repos_exists "TEST_REPO"
    local rc=$?

    assert_equals "0" "$rc" "repo with .git dir exists"
}

# ============================================================================
# repos_ensure Tests
# ============================================================================

test_ensure_already_exists() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 1

    repos_ensure "TEST_REPO"
    local rc=$?

    assert_equals "$E_OK" "$rc" "existing repo returns E_OK"
}

test_ensure_clones_in_mock_mode() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 0

    repos_ensure "TEST_REPO"
    local rc=$?

    assert_equals "$E_OK" "$rc" "clone in mock mode succeeds"

    # Verify repo now marked as existing
    repos_exists "TEST_REPO"
    rc=$?
    assert_equals "0" "$rc" "repo now exists after ensure"
}

test_ensure_not_configured() {
    setup

    local rc=0
    repos_ensure "NONEXISTENT_REPO" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "unconfigured repo returns E_NOT_FOUND"
}

test_ensure_empty_name() {
    setup

    local rc=0
    repos_ensure "" || rc=$?

    assert_equals "$E_INVALID_INPUT" "$rc" "empty name returns E_INVALID_INPUT"
}

# ============================================================================
# repos_update Tests
# ============================================================================

test_update_exists() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 1

    repos_update "TEST_REPO"
    local rc=$?

    assert_equals "$E_OK" "$rc" "update existing repo succeeds in mock mode"
}

test_update_not_cloned() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 0

    local rc=0
    repos_update "TEST_REPO" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "update non-cloned repo returns E_NOT_FOUND"
}

test_update_not_configured() {
    setup

    local rc=0
    repos_update "NONEXISTENT_REPO" || rc=$?

    assert_equals "$E_NOT_FOUND" "$rc" "update unconfigured repo returns E_NOT_FOUND"
}

# ============================================================================
# repos_list Tests
# ============================================================================

test_list_empty() {
    setup

    local result
    result=$(repos_list)

    assert_equals "" "$result" "empty when no repos configured"
}

test_list_single() {
    setup
    repos_mock_set "ONLY_REPO" "git@example.com:only.git" "/path/to/only"

    local result
    result=$(repos_list)

    assert_equals "ONLY_REPO" "$result" "single repo listed"
}

test_list_multiple() {
    setup
    repos_mock_set "REPO_A" "git@example.com:a.git" "/path/to/a"
    repos_mock_set "REPO_B" "git@example.com:b.git" "/path/to/b"

    local result
    result=$(repos_list)

    assert_contains "$result" "REPO_A" "REPO_A in list"
    assert_contains "$result" "REPO_B" "REPO_B in list"
}

# ============================================================================
# repos_mock_reset Tests
# ============================================================================

test_mock_reset_clears_state() {
    setup
    repos_mock_set "TEST_REPO" "git@example.com:test.git" "/path/to/test"
    repos_mock_set_exists "TEST_REPO" 1

    repos_mock_reset

    local rc=0
    repos_is_configured "TEST_REPO" || rc=$?

    assert_equals "1" "$rc" "repo not configured after reset"
}

# ============================================================================
# Run Tests
# ============================================================================

# repos_init tests
test_repos_init_basic
test_repos_init_empty_dir
test_repos_init_missing_repos_conf
test_repos_init_with_comments
test_repos_init_env_expansion

# repos_get_path tests
test_get_path_exists
test_get_path_not_configured
test_get_path_empty_name

# repos_get_url tests
test_get_url_exists
test_get_url_not_configured

# repos_is_configured tests
test_is_configured_true
test_is_configured_false
test_is_configured_empty

# repos_exists tests
test_exists_true
test_exists_false
test_exists_not_configured
test_exists_with_fs_mock

# repos_ensure tests
test_ensure_already_exists
test_ensure_clones_in_mock_mode
test_ensure_not_configured
test_ensure_empty_name

# repos_update tests
test_update_exists
test_update_not_cloned
test_update_not_configured

# repos_list tests
test_list_empty
test_list_single
test_list_multiple

# repos_mock_reset tests
test_mock_reset_clears_state

print_summary
