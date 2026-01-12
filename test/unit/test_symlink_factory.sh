#!/usr/bin/env bash
source "$(dirname "$0")/../test_utils.sh"
source "$(dirname "$0")/../../../../lib/helpers/symlink-factory.sh"

test_symlink_with_backup_new() {
    setup_test_env

    echo "source content" > "$TEST_TEMP_DIR/source.txt"
    symlink_with_backup "$TEST_TEMP_DIR/source.txt" "$TEST_TEMP_DIR/target.txt"

    assert_file_exists "$TEST_TEMP_DIR/target.txt"
    assert_equals "$(readlink "$TEST_TEMP_DIR/target.txt")" "$TEST_TEMP_DIR/source.txt"

    teardown_test_env
}

test_symlink_with_backup_existing() {
    setup_test_env

    echo "old content" > "$TEST_TEMP_DIR/target.txt"
    echo "new content" > "$TEST_TEMP_DIR/source.txt"

    symlink_with_backup "$TEST_TEMP_DIR/source.txt" "$TEST_TEMP_DIR/target.txt"

    # Check symlink points to new source
    assert_equals "$(readlink "$TEST_TEMP_DIR/target.txt")" "$TEST_TEMP_DIR/source.txt"
    # Check backup was created (backup directory from safe_remove)

    teardown_test_env
}

test_create_layer_symlinks() {
    setup_test_env

    # Create layer structure
    mkdir -p "$TEST_TEMP_DIR/layer1" "$TEST_TEMP_DIR/layer2" "$TEST_TEMP_DIR/target"
    echo "layer1 a" > "$TEST_TEMP_DIR/layer1/a.txt"
    echo "layer1 b" > "$TEST_TEMP_DIR/layer1/b.txt"
    echo "layer2 b" > "$TEST_TEMP_DIR/layer2/b.txt"  # Override
    echo "layer2 c" > "$TEST_TEMP_DIR/layer2/c.txt"

    create_layer_symlinks "$TEST_TEMP_DIR/target" "*.txt" "$TEST_TEMP_DIR/layer1" "$TEST_TEMP_DIR/layer2"

    # a.txt from layer1, b.txt from layer2 (override), c.txt from layer2
    assert_equals "$(readlink "$TEST_TEMP_DIR/target/a.txt")" "$TEST_TEMP_DIR/layer1/a.txt"
    assert_equals "$(readlink "$TEST_TEMP_DIR/target/b.txt")" "$TEST_TEMP_DIR/layer2/b.txt"
    assert_equals "$(readlink "$TEST_TEMP_DIR/target/c.txt")" "$TEST_TEMP_DIR/layer2/c.txt"

    teardown_test_env
}

test_symlink_with_backup_new
test_symlink_with_backup_existing
test_create_layer_symlinks
print_summary
