#!/usr/bin/env bash
# test/unit/contracts/test_layer_spec.sh
# Unit tests for contracts/layer_spec.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/contracts/layer_spec.sh"

echo "Testing: contracts/layer_spec"
echo ""

# ============================================================================
# Constructor Tests
# ============================================================================

test_layer_spec_new_creates_spec() {
    declare -A spec
    layer_spec_new spec "base" "local" "configs/git"

    assert_equals "base" "${spec[name]}" "name should be set"
    assert_equals "local" "${spec[source]}" "source should be set"
    assert_equals "configs/git" "${spec[path]}" "path should be set"
    assert_equals "" "${spec[resolved_path]}" "resolved_path should be empty initially"
}

test_layer_spec_new_with_repo_source() {
    declare -A spec
    layer_spec_new spec "work" "STRIPE_DOTFILES" "stripe/git"

    assert_equals "work" "${spec[name]}" "name should be set"
    assert_equals "STRIPE_DOTFILES" "${spec[source]}" "source should be repo name"
    assert_equals "stripe/git" "${spec[path]}" "path should be set"
}

# ============================================================================
# Validation Tests - Valid Cases
# ============================================================================

test_layer_spec_validate_valid_local() {
    declare -A spec
    layer_spec_new spec "base" "local" "configs/git"

    layer_spec_validate spec
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid local spec should pass validation"
}

test_layer_spec_validate_valid_repo() {
    declare -A spec
    layer_spec_new spec "work" "STRIPE_DOTFILES" "configs/git"

    layer_spec_validate spec
    local rc=$?

    assert_equals "$E_OK" "$rc" "valid repo spec should pass validation"
}

test_layer_spec_validate_name_with_hyphens() {
    declare -A spec
    layer_spec_new spec "work-macbook" "local" "configs/git"

    layer_spec_validate spec
    local rc=$?

    assert_equals "$E_OK" "$rc" "name with hyphens should be valid"
}

test_layer_spec_validate_name_with_underscores() {
    declare -A spec
    layer_spec_new spec "work_laptop" "local" "configs/git"

    layer_spec_validate spec
    local rc=$?

    assert_equals "$E_OK" "$rc" "name with underscores should be valid"
}

test_layer_spec_validate_repo_with_numbers() {
    declare -A spec
    layer_spec_new spec "base" "DOTFILES2" "configs/git"

    layer_spec_validate spec
    local rc=$?

    assert_equals "$E_OK" "$rc" "repo name with numbers should be valid"
}

# ============================================================================
# Validation Tests - Invalid Cases
# ============================================================================

test_layer_spec_validate_missing_name() {
    declare -A spec
    layer_spec_new spec "" "local" "configs/git"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing name should fail validation"
}

test_layer_spec_validate_missing_source() {
    declare -A spec
    layer_spec_new spec "base" "" "configs/git"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing source should fail validation"
}

test_layer_spec_validate_missing_path() {
    declare -A spec
    layer_spec_new spec "base" "local" ""

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing path should fail validation"
}

test_layer_spec_validate_invalid_source_lowercase() {
    declare -A spec
    layer_spec_new spec "base" "stripe_dotfiles" "configs/git"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "lowercase repo name should fail validation"
}

test_layer_spec_validate_invalid_source_mixed() {
    declare -A spec
    layer_spec_new spec "base" "Stripe_Dotfiles" "configs/git"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "mixed case repo name should fail validation"
}

test_layer_spec_validate_absolute_path() {
    declare -A spec
    layer_spec_new spec "base" "local" "/absolute/path"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "absolute path should fail validation"
}

test_layer_spec_validate_invalid_name_spaces() {
    declare -A spec
    layer_spec_new spec "base layer" "local" "configs/git"

    layer_spec_validate spec 2>/dev/null
    local rc=$?

    assert_equals "$E_VALIDATION" "$rc" "name with spaces should fail validation"
}

# ============================================================================
# Setter/Getter Tests
# ============================================================================

test_layer_spec_set_resolved() {
    declare -A spec
    layer_spec_new spec "base" "local" "configs/git"

    layer_spec_set_resolved spec "/home/user/.dotfiles/configs/git"

    assert_equals "/home/user/.dotfiles/configs/git" "${spec[resolved_path]}" \
        "resolved_path should be updated"
}

test_layer_spec_getters() {
    declare -A spec
    layer_spec_new spec "work" "STRIPE_DOTFILES" "stripe/git"
    layer_spec_set_resolved spec "/repos/stripe/git"

    local name source path resolved
    name=$(layer_spec_get_name spec)
    source=$(layer_spec_get_source spec)
    path=$(layer_spec_get_path spec)
    resolved=$(layer_spec_get_resolved spec)

    assert_equals "work" "$name" "get_name should return name"
    assert_equals "STRIPE_DOTFILES" "$source" "get_source should return source"
    assert_equals "stripe/git" "$path" "get_path should return path"
    assert_equals "/repos/stripe/git" "$resolved" "get_resolved should return resolved_path"
}

# ============================================================================
# Error Message Tests
# ============================================================================

test_layer_spec_validate_outputs_errors_to_stderr() {
    declare -A spec
    layer_spec_new spec "" "" ""

    local stderr_output
    stderr_output=$(layer_spec_validate spec 2>&1 >/dev/null) || true

    assert_contains "$stderr_output" "validation failed" "should output validation failure message"
    assert_contains "$stderr_output" "name is required" "should list name error"
    assert_contains "$stderr_output" "source is required" "should list source error"
    assert_contains "$stderr_output" "path is required" "should list path error"
}

# ============================================================================
# Run Tests
# ============================================================================

test_layer_spec_new_creates_spec
test_layer_spec_new_with_repo_source

test_layer_spec_validate_valid_local
test_layer_spec_validate_valid_repo
test_layer_spec_validate_name_with_hyphens
test_layer_spec_validate_name_with_underscores
test_layer_spec_validate_repo_with_numbers

test_layer_spec_validate_missing_name
test_layer_spec_validate_missing_source
test_layer_spec_validate_missing_path
test_layer_spec_validate_invalid_source_lowercase
test_layer_spec_validate_invalid_source_mixed
test_layer_spec_validate_absolute_path
test_layer_spec_validate_invalid_name_spaces

test_layer_spec_set_resolved
test_layer_spec_getters
test_layer_spec_validate_outputs_errors_to_stderr

print_summary
