# Test Framework

## Running Tests
```bash
bash lib/dotfiles-system/test/run_tests.sh           # All tests
bash lib/dotfiles-system/test/unit/test_foo.sh       # Single test
```

## Writing Tests

Use an existing test as your template. Key conventions:

```bash
#!/usr/bin/env bash
source "$(dirname "$0")/../test_utils.sh"
source "$(dirname "$0")/../../lib/whatever.sh"  # Adjust path as needed

test_something() {
    setup_test_env  # Creates $TEST_TEMP_DIR

    # Your test logic here
    echo "data" > "$TEST_TEMP_DIR/file.txt"

    assert_equals "expected" "actual" "message"
    assert_contains "$haystack" "needle"
    assert_file_exists "$TEST_TEMP_DIR/file.txt"
    assert_success "command_that_should_pass"
    assert_failure "command_that_should_fail"

    teardown_test_env
}

test_something
print_summary
```

## Important Notes

- Variable is `$TEST_TEMP_DIR` (not `$TEST_DIR`)
- Paths are relative to the test file location
- Run your test directly with `bash test_file.sh` before debugging failures
