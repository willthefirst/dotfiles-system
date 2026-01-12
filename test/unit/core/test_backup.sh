#!/usr/bin/env bash
# test/unit/core/test_backup.sh
# Unit tests for core/backup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test (includes fs.sh, log.sh, errors.sh)
source "$SCRIPT_DIR/../../../lib/core/backup.sh"

echo "Testing: core/backup"
echo ""

# Setup: Initialize mock mode before each test
setup() {
    fs_init "mock"
    fs_mock_reset

    declare -gA log_cfg=([output]="mock" [level]="debug")
    log_init log_cfg
    log_mock_reset

    declare -gA backup_cfg=([dir]="/backups")
    backup_init backup_cfg
}

# Test 1: backup_init creates backup directory
test_backup_init_creates_dir() {
    setup

    if fs_mock_assert_call "mkdir:/backups"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: backup_init creates backup directory"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: backup_init should create backup directory"
    fi
}

# Test 2: backup_get_dir returns configured directory
test_backup_get_dir() {
    setup
    local dir
    dir=$(backup_get_dir)
    assert_equals "/backups" "$dir" "backup_get_dir returns configured directory"
}

# Test 3: backup_create on non-existent file returns success
test_backup_create_nonexistent() {
    setup
    local result_path=""

    backup_create "/nonexistent/file.txt" result_path
    local rc=$?

    assert_equals "0" "$rc" "backup_create on non-existent returns E_OK"
    assert_equals "" "$result_path" "backup_create on non-existent returns empty path"
}

# Test 4: backup_create backs up file
test_backup_create_file() {
    setup
    fs_mock_set "/home/user/.config" "my config data"

    local result_path=""
    backup_create "/home/user/.config" result_path
    local rc=$?

    assert_equals "0" "$rc" "backup_create returns E_OK"

    # Backup path should be in backup dir with timestamp
    assert_contains "$result_path" "/backups/.config." "Backup path should be in backup dir"

    # Backup should contain original content
    local content
    content=$(fs_read "$result_path")
    assert_equals "my config data" "$content" "Backup should contain original content"
}

# Test 5: backup_create backs up symlink
test_backup_create_symlink() {
    setup
    fs_mock_set_symlink "/home/user/.bashrc" "/dotfiles/bashrc"

    local result_path=""
    backup_create "/home/user/.bashrc" result_path
    local rc=$?

    assert_equals "0" "$rc" "backup_create returns E_OK for symlink"

    # Backup should contain symlink marker
    local content
    content=$(fs_read "$result_path")
    assert_equals "__SYMLINK:/dotfiles/bashrc" "$content" "Backup should contain symlink target"
}

# Test 6: backup_restore restores file
test_backup_restore_file() {
    setup
    # Create a "backup"
    fs_mock_set "/backups/config.20240115_120000" "restored content"

    local rc
    backup_restore "/backups/config.20240115_120000" "/home/user/.config"
    rc=$?

    assert_equals "0" "$rc" "backup_restore returns E_OK"

    local content
    content=$(fs_read "/home/user/.config")
    assert_equals "restored content" "$content" "File should be restored with backup content"
}

# Test 7: backup_restore restores symlink
test_backup_restore_symlink() {
    setup
    # Create a symlink "backup"
    fs_mock_set "/backups/bashrc.20240115_120000" "__SYMLINK:/dotfiles/bashrc"

    local rc
    backup_restore "/backups/bashrc.20240115_120000" "/home/user/.bashrc"
    rc=$?

    assert_equals "0" "$rc" "backup_restore returns E_OK for symlink"

    if fs_is_symlink "/home/user/.bashrc"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Restored path is a symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Restored path should be a symlink"
    fi

    local target
    target=$(fs_readlink "/home/user/.bashrc")
    assert_equals "/dotfiles/bashrc" "$target" "Symlink should point to original target"
}

# Test 8: backup_restore fails for missing backup
test_backup_restore_missing() {
    setup

    local rc=0
    backup_restore "/backups/nonexistent" "/home/user/.config" 2>/dev/null || rc=$?

    assert_equals "3" "$rc" "backup_restore returns E_NOT_FOUND for missing backup"
}

# Test 9: backup_list lists backups
test_backup_list() {
    setup
    fs_mock_set "/backups/file1.20240115_120000" "content1"
    fs_mock_set "/backups/file2.20240115_130000" "content2"

    local listing
    listing=$(backup_list)

    assert_contains "$listing" "file1.20240115_120000" "Listing should include file1"
    assert_contains "$listing" "file2.20240115_130000" "Listing should include file2"
}

# Test 10: backup_create uses timestamp in filename
test_backup_create_uses_timestamp() {
    setup
    fs_mock_set "/home/user/.gitconfig" "git settings"

    local result_path=""
    backup_create "/home/user/.gitconfig" result_path

    # Should match pattern: /backups/.gitconfig.YYYYMMDD_HHMMSS
    if [[ "$result_path" =~ /backups/\.gitconfig\.[0-9]{8}_[0-9]{6} ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Backup path contains timestamp"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Backup path should contain timestamp: $result_path"
    fi
}

# Test 11: backup_cleanup logs operation (mock mode)
test_backup_cleanup() {
    setup
    log_mock_reset

    backup_cleanup 30

    if log_mock_assert "Cleaning up"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: backup_cleanup logs cleanup operation"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: backup_cleanup should log cleanup operation"
    fi
}

# Test 12: backup_restore overwrites existing file
test_backup_restore_overwrites() {
    setup
    fs_mock_set "/home/user/.config" "old content"
    fs_mock_set "/backups/config.backup" "backup content"

    backup_restore "/backups/config.backup" "/home/user/.config"

    local content
    content=$(fs_read "/home/user/.config")
    assert_equals "backup content" "$content" "Restored content should overwrite existing"
}

# Run all tests
test_backup_init_creates_dir
test_backup_get_dir
test_backup_create_nonexistent
test_backup_create_file
test_backup_create_symlink
test_backup_restore_file
test_backup_restore_symlink
test_backup_restore_missing
test_backup_list
test_backup_create_uses_timestamp
test_backup_cleanup
test_backup_restore_overwrites

print_summary
