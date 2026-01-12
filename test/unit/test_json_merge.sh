#!/usr/bin/env bash
source "$(dirname "$0")/../test_utils.sh"
source "$(dirname "$0")/../../../../lib/helpers/json-merge.sh"

test_json_deep_merge_basic() {
    setup_test_env

    echo '{"a": 1, "b": 2}' > "$TEST_TEMP_DIR/base.json"
    echo '{"b": 3, "c": 4}' > "$TEST_TEMP_DIR/overlay.json"

    json_deep_merge "$TEST_TEMP_DIR/output.json" "$TEST_TEMP_DIR/base.json" "$TEST_TEMP_DIR/overlay.json"

    local result=$(cat "$TEST_TEMP_DIR/output.json")
    assert_contains "$result" '"a": 1'
    assert_contains "$result" '"b": 3'  # overlay wins
    assert_contains "$result" '"c": 4'

    teardown_test_env
}

test_json_deep_merge_nested() {
    setup_test_env

    echo '{"editor": {"fontSize": 14, "tabSize": 2}}' > "$TEST_TEMP_DIR/base.json"
    echo '{"editor": {"fontSize": 16}}' > "$TEST_TEMP_DIR/overlay.json"

    json_deep_merge "$TEST_TEMP_DIR/output.json" "$TEST_TEMP_DIR/base.json" "$TEST_TEMP_DIR/overlay.json"

    # Should have fontSize=16 but preserve tabSize=2
    local result=$(cat "$TEST_TEMP_DIR/output.json")
    assert_contains "$result" '"fontSize": 16'
    assert_contains "$result" '"tabSize": 2'

    teardown_test_env
}

test_json_validate_valid() {
    setup_test_env
    echo '{"valid": true}' > "$TEST_TEMP_DIR/valid.json"
    assert_success "json_validate $TEST_TEMP_DIR/valid.json"
    teardown_test_env
}

test_json_validate_invalid() {
    setup_test_env
    echo '{invalid json' > "$TEST_TEMP_DIR/invalid.json"
    assert_failure "json_validate $TEST_TEMP_DIR/invalid.json"
    teardown_test_env
}

# Run tests
test_json_deep_merge_basic
test_json_deep_merge_nested
test_json_validate_valid
test_json_validate_invalid
print_summary
