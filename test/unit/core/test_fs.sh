#!/usr/bin/env bash
# test/unit/core/test_fs.sh
# Unit tests for core/fs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/core/fs.sh"

echo "Testing: core/fs"
echo ""

# Setup: Initialize mock mode before each test
setup() {
    fs_init "mock"
    fs_mock_reset
}

# Test 1: fs_init sets backend
test_fs_init_sets_backend() {
    fs_init "mock"
    local backend
    backend=$(fs_get_backend)
    assert_equals "mock" "$backend" "fs_init should set mock backend"
}

# Test 2: fs_write and fs_read work together
test_fs_write_read() {
    setup
    fs_write "/test/file.txt" "hello world"

    local content
    content=$(fs_read "/test/file.txt")
    assert_equals "hello world" "$content" "fs_read should return written content"
}

# Test 3: fs_exists returns true for existing file
test_fs_exists_file() {
    setup
    fs_mock_set "/test/file.txt" "content"

    if fs_exists "/test/file.txt"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_exists returns true for existing file"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_exists should return true for existing file"
    fi
}

# Test 4: fs_exists returns false for missing file
test_fs_exists_missing() {
    setup

    if ! fs_exists "/nonexistent"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_exists returns false for missing file"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_exists should return false for missing file"
    fi
}

# Test 5: fs_is_file returns true for file
test_fs_is_file() {
    setup
    fs_mock_set "/test/file.txt" "content"

    if fs_is_file "/test/file.txt"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_is_file returns true for file"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_is_file should return true for file"
    fi
}

# Test 6: fs_is_dir returns true for directory
test_fs_is_dir() {
    setup
    fs_mock_set_dir "/test/dir"

    if fs_is_dir "/test/dir"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_is_dir returns true for directory"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_is_dir should return true for directory"
    fi
}

# Test 7: fs_is_symlink returns true for symlink
test_fs_is_symlink() {
    setup
    fs_mock_set_symlink "/test/link" "/target"

    if fs_is_symlink "/test/link"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_is_symlink returns true for symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_is_symlink should return true for symlink"
    fi
}

# Test 8: fs_remove removes file
test_fs_remove() {
    setup
    fs_mock_set "/test/file.txt" "content"
    fs_remove "/test/file.txt"

    if ! fs_exists "/test/file.txt"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_remove removes file"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_remove should remove file"
    fi
}

# Test 9: fs_mkdir creates directory
test_fs_mkdir() {
    setup
    fs_mkdir "/test/newdir"

    if fs_is_dir "/test/newdir"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_mkdir creates directory"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_mkdir should create directory"
    fi
}

# Test 10: fs_symlink creates symlink
test_fs_symlink() {
    setup
    fs_symlink "/target/file" "/test/link"

    if fs_is_symlink "/test/link"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_symlink creates symlink"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_symlink should create symlink"
    fi

    local target
    target=$(fs_readlink "/test/link")
    assert_equals "/target/file" "$target" "fs_readlink should return target"
}

# Test 11: fs_append appends content
test_fs_append() {
    setup
    fs_write "/test/file.txt" "hello"
    fs_append "/test/file.txt" " world"

    local content
    content=$(fs_read "/test/file.txt")
    assert_equals "hello world" "$content" "fs_append should append content"
}

# Test 12: fs_copy copies file
test_fs_copy() {
    setup
    fs_mock_set "/src/file.txt" "original content"
    fs_copy "/src/file.txt" "/dst/file.txt"

    local content
    content=$(fs_read "/dst/file.txt")
    assert_equals "original content" "$content" "fs_copy should copy content"
}

# Test 13: fs_mock_calls tracks operations
test_fs_mock_calls() {
    setup
    fs_write "/test/file.txt" "content"
    fs_read "/test/file.txt"

    local calls
    calls=$(fs_mock_calls)
    assert_contains "$calls" "write:/test/file.txt" "Calls should include write"
    assert_contains "$calls" "read:/test/file.txt" "Calls should include read"
}

# Test 14: fs_mock_assert_written validates content
test_fs_mock_assert_written() {
    setup
    fs_write "/test/file.txt" "expected content"

    if fs_mock_assert_written "/test/file.txt" "expected content"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_mock_assert_written validates correct content"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_mock_assert_written should pass for correct content"
    fi
}

# Test 15: fs_mock_assert_call finds operation
test_fs_mock_assert_call() {
    setup
    fs_mkdir "/test/dir"

    if fs_mock_assert_call "mkdir:/test/dir"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_mock_assert_call finds mkdir operation"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_mock_assert_call should find mkdir operation"
    fi
}

# Test 16: fs_list lists directory contents
test_fs_list() {
    setup
    fs_mock_set "/dir/file1.txt" "content1"
    fs_mock_set "/dir/file2.txt" "content2"

    local listing
    listing=$(fs_list "/dir")
    assert_contains "$listing" "file1.txt" "Listing should include file1.txt"
    assert_contains "$listing" "file2.txt" "Listing should include file2.txt"
}

# Test 17: fs_remove_rf removes directory recursively
test_fs_remove_rf() {
    setup
    fs_mock_set_dir "/dir"
    fs_mock_set "/dir/file.txt" "content"
    fs_mock_set "/dir/subdir/nested.txt" "nested"

    fs_remove_rf "/dir"

    if ! fs_exists "/dir"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_remove_rf removes directory"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_remove_rf should remove directory"
    fi

    if ! fs_exists "/dir/file.txt"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_remove_rf removes children"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_remove_rf should remove children"
    fi
}

# Test 18: fs_mock_reset clears all state
test_fs_mock_reset() {
    setup
    fs_mock_set "/test/file.txt" "content"
    fs_mock_reset

    if ! fs_exists "/test/file.txt"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: fs_mock_reset clears files"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: fs_mock_reset should clear files"
    fi
}

# Run all tests
test_fs_init_sets_backend
test_fs_write_read
test_fs_exists_file
test_fs_exists_missing
test_fs_is_file
test_fs_is_dir
test_fs_is_symlink
test_fs_remove
test_fs_mkdir
test_fs_symlink
test_fs_append
test_fs_copy
test_fs_mock_calls
test_fs_mock_assert_written
test_fs_mock_assert_call
test_fs_list
test_fs_remove_rf
test_fs_mock_reset

print_summary
