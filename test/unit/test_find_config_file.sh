#!/usr/bin/env bash
# test/unit/test_find_config_file.sh
# Unit tests for find_config_file function

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"
source "$SCRIPT_DIR/../../lib/utils.sh"

echo "Testing: find_config_file"
echo ""

# Setup test environment
setup_test_env

# Create test fixtures
setup_fixtures() {
    # Create a layer directory with various config files
    mkdir -p "$TEST_TEMP_DIR/layer1"
    echo "config content" > "$TEST_TEMP_DIR/layer1/config"

    mkdir -p "$TEST_TEMP_DIR/layer2"
    echo "target content" > "$TEST_TEMP_DIR/layer2/target.conf"

    mkdir -p "$TEST_TEMP_DIR/layer3"
    echo "init content" > "$TEST_TEMP_DIR/layer3/init"

    mkdir -p "$TEST_TEMP_DIR/layer4"
    echo "json content" > "$TEST_TEMP_DIR/layer4/config.json"

    mkdir -p "$TEST_TEMP_DIR/empty_layer"

    # Create a file-as-layer
    echo "single file" > "$TEST_TEMP_DIR/single_file.conf"
}

setup_fixtures

# Test 1: Find config file by name
test_find_exact_name() {
    local result
    result=$(find_config_file "$TEST_TEMP_DIR/layer2" "target.conf") || true
    assert_equals "$TEST_TEMP_DIR/layer2/target.conf" "$result" "Should find exact target name"
}

# Test 2: Find generic config file
test_find_generic_config() {
    local result
    result=$(find_config_file "$TEST_TEMP_DIR/layer1" "nonexistent") || true
    assert_equals "$TEST_TEMP_DIR/layer1/config" "$result" "Should fall back to 'config'"
}

# Test 3: Find init file
test_find_init() {
    local result
    result=$(find_config_file "$TEST_TEMP_DIR/layer3" "nonexistent") || true
    assert_equals "$TEST_TEMP_DIR/layer3/init" "$result" "Should fall back to 'init'"
}

# Test 4: Return file if layer is a file itself
test_layer_is_file() {
    local result
    result=$(find_config_file "$TEST_TEMP_DIR/single_file.conf" "anything") || true
    assert_equals "$TEST_TEMP_DIR/single_file.conf" "$result" "Should return file if layer is a file"
}

# Test 5: Find JSON file with extension hint
test_find_json_with_extension() {
    local result
    result=$(find_config_file "$TEST_TEMP_DIR/layer4" "nonexistent" "json") || true
    assert_equals "$TEST_TEMP_DIR/layer4/config.json" "$result" "Should find config.json with extension hint"
}

# Test 6: Return failure for non-existent layer
test_nonexistent_layer() {
    if find_config_file "$TEST_TEMP_DIR/nonexistent" "anything" &>/dev/null; then
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: Should return error for non-existent layer"
    else
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: Should return error for non-existent layer"
    fi
}

# Test 7: Return failure for empty layer
test_empty_layer() {
    if find_config_file "$TEST_TEMP_DIR/empty_layer" "anything" &>/dev/null; then
        ((TESTS_RUN++))
        ((TESTS_FAILED++))
        echo -e "${RED}FAIL${NC}: Should return error for empty layer"
    else
        ((TESTS_RUN++))
        ((TESTS_PASSED++))
        echo -e "${GREEN}PASS${NC}: Should return error for empty layer"
    fi
}

# Run all tests
test_find_exact_name
test_find_generic_config
test_find_init
test_layer_is_file
test_find_json_with_extension
test_nonexistent_layer
test_empty_layer

# Cleanup
teardown_test_env

print_summary
