#!/usr/bin/env bash
# test/unit/test_safe_write.sh
# Unit tests for safe-write.sh functions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"

# Set DOTFILES_DIR for sourcing
export DOTFILES_DIR="$SCRIPT_DIR/../../../.."
source "$DOTFILES_DIR/lib/helpers/safe-write.sh"

echo "Testing: safe-write.sh functions"
echo ""

# Setup test environment
setup_test_env

# =============================================================================
# safe_write_file tests
# =============================================================================

test_safe_write_file_creates_file() {
    local target="$TEST_TEMP_DIR/new_file.txt"
    local content="hello world"

    safe_write_file "$target" "$content"

    assert_file_exists "$target" "File should be created"

    local actual
    actual=$(cat "$target")
    assert_equals "$content" "$actual" "Content should match"
}

test_safe_write_file_backs_up_existing() {
    local target="$TEST_TEMP_DIR/existing.txt"
    echo "original content" > "$target"

    safe_write_file "$target" "new content"

    # Check backup was created
    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "existing.txt_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Backup should be created"

    # Check new content
    local actual
    actual=$(cat "$target")
    assert_equals "new content" "$actual" "New content should be written"
}

test_safe_write_file_creates_parent_dirs() {
    local target="$TEST_TEMP_DIR/deep/nested/dir/file.txt"

    safe_write_file "$target" "content"

    assert_file_exists "$target" "File in nested dir should be created"
}

test_safe_write_file_from_stdin() {
    local target="$TEST_TEMP_DIR/stdin_file.txt"

    echo "stdin content" | safe_write_file "$target"

    local actual
    actual=$(cat "$target")
    assert_equals "stdin content" "$actual" "Content from stdin should be written"
}

# =============================================================================
# safe_write_heredoc tests
# =============================================================================

test_safe_write_heredoc() {
    local target="$TEST_TEMP_DIR/heredoc.txt"

    safe_write_heredoc "$target" << 'EOF'
line 1
line 2
EOF

    assert_file_exists "$target" "Heredoc file should be created"

    local lines
    lines=$(wc -l < "$target" | tr -d ' ')
    assert_equals "2" "$lines" "Should have 2 lines"
}

test_safe_write_heredoc_backs_up_existing() {
    local target="$TEST_TEMP_DIR/heredoc_existing.txt"
    echo "old" > "$target"

    safe_write_heredoc "$target" << 'EOF'
new
EOF

    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "heredoc_existing.txt_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Backup should be created for heredoc"
}

# =============================================================================
# safe_append_file tests
# =============================================================================

test_safe_append_file_appends() {
    local target="$TEST_TEMP_DIR/append.txt"
    echo "line1" > "$target"

    safe_append_file "$target" "line2"

    local content
    content=$(cat "$target")
    assert_contains "$content" "line1" "Original content preserved"
    assert_contains "$content" "line2" "New content appended"
}

test_safe_append_file_backs_up_once() {
    local target="$TEST_TEMP_DIR/append_backup.txt"
    echo "original" > "$target"

    # Append multiple times
    safe_append_file "$target" "append1"
    safe_append_file "$target" "append2"
    safe_append_file "$target" "append3"

    # Should only have ONE backup (first append)
    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "append_backup.txt_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Only one backup for multiple appends"
}

test_safe_append_file_creates_if_missing() {
    local target="$TEST_TEMP_DIR/append_new.txt"

    safe_append_file "$target" "first line"

    assert_file_exists "$target" "File should be created on append"
}

# =============================================================================
# safe_jq_write tests
# =============================================================================

test_safe_jq_write_basic() {
    local target="$TEST_TEMP_DIR/output.json"
    echo '{"a": 1}' > "$TEST_TEMP_DIR/input.json"

    safe_jq_write "$target" '.a' "$TEST_TEMP_DIR/input.json"

    local actual
    actual=$(cat "$target")
    assert_equals "1" "$actual" "jq output should be written"
}

test_safe_jq_write_with_slurp() {
    local target="$TEST_TEMP_DIR/merged.json"
    echo '["a"]' > "$TEST_TEMP_DIR/arr1.json"
    echo '["b"]' > "$TEST_TEMP_DIR/arr2.json"

    safe_jq_write "$target" -s 'add' "$TEST_TEMP_DIR/arr1.json" "$TEST_TEMP_DIR/arr2.json"

    local actual
    actual=$(cat "$target")
    assert_contains "$actual" '"a"' "Should contain a"
    assert_contains "$actual" '"b"' "Should contain b"
}

test_safe_jq_write_backs_up_existing() {
    local target="$TEST_TEMP_DIR/jq_existing.json"
    echo '{"old": true}' > "$target"
    echo '{"new": true}' > "$TEST_TEMP_DIR/new.json"

    safe_jq_write "$target" '.' "$TEST_TEMP_DIR/new.json"

    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "jq_existing.json_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Backup should be created for jq write"
}

# =============================================================================
# safe_remove error handling tests
# =============================================================================

test_safe_remove_returns_error_on_unwritable_backup_dir() {
    local target="$TEST_TEMP_DIR/file_to_remove.txt"
    echo "content" > "$target"

    # Create unwritable backup dir
    local bad_backup="$TEST_TEMP_DIR/unwritable_backup"
    mkdir -p "$bad_backup"
    chmod 000 "$bad_backup"

    local result
    result=$(DOTFILES_BACKUP_DIR="$bad_backup" safe_remove "$target" 2>&1) && local exit_code=$? || local exit_code=$?

    # Restore permissions for cleanup
    chmod 755 "$bad_backup"

    if [[ $exit_code -ne 0 ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: safe_remove returns error for unwritable backup dir"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: safe_remove should fail for unwritable backup dir"
    fi
}

test_safe_remove_force_mode() {
    local target="$TEST_TEMP_DIR/force_remove.txt"
    echo "content" > "$target"

    DOTFILES_FORCE=1 safe_remove "$target"

    if [[ ! -e "$target" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: DOTFILES_FORCE=1 removes file"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: DOTFILES_FORCE=1 should remove file"
    fi

    # Should NOT create backup in force mode
    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "force_remove.txt_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "0" "$backup_count" "Force mode should not create backup"
}

# =============================================================================
# safe_write_file failure handling
# =============================================================================

test_safe_write_file_fails_on_backup_failure() {
    local target="$TEST_TEMP_DIR/write_fail_test.txt"
    echo "existing" > "$target"

    # Create unwritable backup dir
    local bad_backup="$TEST_TEMP_DIR/bad_backup2"
    mkdir -p "$bad_backup"
    chmod 000 "$bad_backup"

    local result
    DOTFILES_BACKUP_DIR="$bad_backup" safe_write_file "$target" "new content" 2>&1 && local exit_code=$? || local exit_code=$?

    # Restore permissions for cleanup
    chmod 755 "$bad_backup"

    if [[ $exit_code -ne 0 ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: safe_write_file fails when backup fails"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: safe_write_file should fail when backup fails"
    fi

    # Original file should be preserved
    local content
    content=$(cat "$target")
    assert_equals "existing" "$content" "Original content should be preserved on failure"
}

# =============================================================================
# Run all tests
# =============================================================================

test_safe_write_file_creates_file
test_safe_write_file_backs_up_existing
test_safe_write_file_creates_parent_dirs
test_safe_write_file_from_stdin
test_safe_write_heredoc
test_safe_write_heredoc_backs_up_existing
test_safe_append_file_appends
test_safe_append_file_backs_up_once
test_safe_append_file_creates_if_missing
test_safe_jq_write_basic
test_safe_jq_write_with_slurp
test_safe_jq_write_backs_up_existing
test_safe_remove_returns_error_on_unwritable_backup_dir
test_safe_remove_force_mode
test_safe_write_file_fails_on_backup_failure

# Cleanup
teardown_test_env

print_summary
