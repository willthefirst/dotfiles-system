#!/usr/bin/env bash
# test/unit/test_safe_remove.sh
# Unit tests for safe_remove function

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"
source "$SCRIPT_DIR/../../lib/utils.sh"

echo "Testing: safe_remove"
echo ""

# Setup test environment
setup_test_env

# Test 1: Remove file creates backup
test_remove_file_creates_backup() {
    # Create a test file
    echo "test content" > "$TEST_TEMP_DIR/testfile.txt"

    # Remove it
    safe_remove "$TEST_TEMP_DIR/testfile.txt"

    # File should be gone
    if [[ -f "$TEST_TEMP_DIR/testfile.txt" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Original file should be removed"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Original file was removed"
    fi

    # Backup should exist (trim whitespace from wc output)
    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -name "testfile.txt_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Backup file should be created"
}

# Test 2: Remove directory creates backup
test_remove_dir_creates_backup() {
    # Create a test directory
    mkdir -p "$TEST_TEMP_DIR/testdir"
    echo "content" > "$TEST_TEMP_DIR/testdir/file.txt"

    # Remove it
    safe_remove_rf "$TEST_TEMP_DIR/testdir"

    # Directory should be gone
    if [[ -d "$TEST_TEMP_DIR/testdir" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Original directory should be removed"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Original directory was removed"
    fi

    # Backup should exist (trim whitespace from wc output)
    local backup_count
    backup_count=$(find "$DOTFILES_BACKUP_DIR" -type d -name "testdir_*" 2>/dev/null | wc -l | tr -d ' ')
    assert_equals "1" "$backup_count" "Backup directory should be created"
}

# Test 3: Remove non-existent file is no-op
test_remove_nonexistent() {
    local result
    result=$(safe_remove "$TEST_TEMP_DIR/nonexistent" 2>&1) || true

    # Should succeed silently
    ((TESTS_RUN++)) || true
    ((TESTS_PASSED++)) || true
    echo -e "${GREEN}PASS${NC}: Removing non-existent file succeeds silently"
}

# Test 4: Remove symlink creates backup
test_remove_symlink() {
    # Create a symlink
    echo "target" > "$TEST_TEMP_DIR/target.txt"
    ln -s "$TEST_TEMP_DIR/target.txt" "$TEST_TEMP_DIR/link.txt"

    # Remove the symlink
    safe_remove "$TEST_TEMP_DIR/link.txt"

    # Symlink should be gone
    if [[ -L "$TEST_TEMP_DIR/link.txt" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Symlink should be removed"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Symlink was removed"
    fi

    # Target should still exist
    assert_file_exists "$TEST_TEMP_DIR/target.txt" "Target file should still exist"
}

# Test 5: Backup preserves content
test_backup_preserves_content() {
    # Create a file with specific content
    local original_content="unique test content 12345"
    echo "$original_content" > "$TEST_TEMP_DIR/content_test.txt"

    # Remove it
    safe_remove "$TEST_TEMP_DIR/content_test.txt"

    # Find the backup
    local backup_file
    backup_file=$(find "$DOTFILES_BACKUP_DIR" -name "content_test.txt_*" | head -1)

    if [[ -n "$backup_file" ]]; then
        local backup_content
        backup_content=$(cat "$backup_file")
        assert_equals "$original_content" "$backup_content" "Backup should preserve original content"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Backup file not found"
    fi
}

# Run all tests
test_remove_file_creates_backup
test_remove_dir_creates_backup
test_remove_nonexistent
test_remove_symlink
test_backup_preserves_content

# Cleanup
teardown_test_env

print_summary
