#!/usr/bin/env bash
# test/unit/config/test_validator.sh
# Unit tests for config/validator.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

# Module under test
source "$SCRIPT_DIR/../../../lib/config/validator.sh"

echo "Testing: config/validator"
echo ""

# ============================================================================
# config_parse_layer_spec Tests
# ============================================================================

test_parse_layer_spec_local() {
    local source path

    config_parse_layer_spec "local:configs/git" source path
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for valid spec"
    assert_equals "local" "$source" "source should be 'local'"
    assert_equals "configs/git" "$path" "path should be 'configs/git'"
}

test_parse_layer_spec_external() {
    local source path

    config_parse_layer_spec "STRIPE_DOTFILES:git" source path
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for valid spec"
    assert_equals "STRIPE_DOTFILES" "$source" "source should be 'STRIPE_DOTFILES'"
    assert_equals "git" "$path" "path should be 'git'"
}

test_parse_layer_spec_nested_path() {
    local source path

    config_parse_layer_spec "local:configs/nvim/lua" source path
    local rc=$?

    assert_equals "0" "$rc" "should return 0 for nested path"
    assert_equals "local" "$source" "source should be 'local'"
    assert_equals "configs/nvim/lua" "$path" "path should include subdirs"
}

test_parse_layer_spec_invalid_no_colon() {
    local source path

    local rc=0
    config_parse_layer_spec "invalid_spec_no_colon" source path || rc=$?

    assert_equals "1" "$rc" "should return 1 for spec without colon"
}

test_parse_layer_spec_invalid_empty_source() {
    local source path

    local rc=0
    config_parse_layer_spec ":configs/git" source path || rc=$?

    assert_equals "1" "$rc" "should return 1 for empty source"
}

test_parse_layer_spec_invalid_empty_path() {
    local source path

    local rc=0
    config_parse_layer_spec "local:" source path || rc=$?

    assert_equals "1" "$rc" "should return 1 for empty path"
}

# ============================================================================
# config_resolve_hook_path Tests
# ============================================================================

test_resolve_hook_path_builtin() {
    local result
    result=$(config_resolve_hook_path "builtin:symlink" "/tools/git")

    assert_equals "builtin:symlink" "$result" "builtin hooks unchanged"
}

test_resolve_hook_path_builtin_concat() {
    local result
    result=$(config_resolve_hook_path "builtin:concat" "/tools/zsh")

    assert_equals "builtin:concat" "$result" "builtin:concat unchanged"
}

test_resolve_hook_path_relative_dotslash() {
    local result
    result=$(config_resolve_hook_path "./merge.sh" "/tools/git")

    assert_equals "/tools/git/merge.sh" "$result" "./relative resolved to tool_dir"
}

test_resolve_hook_path_relative_plain() {
    local result
    result=$(config_resolve_hook_path "merge.sh" "/tools/git")

    assert_equals "/tools/git/merge.sh" "$result" "plain relative resolved to tool_dir"
}

test_resolve_hook_path_absolute() {
    local result
    result=$(config_resolve_hook_path "/absolute/path/to/hook.sh" "/tools/git")

    assert_equals "/absolute/path/to/hook.sh" "$result" "absolute paths unchanged"
}

# ============================================================================
# config_build_tool_config Tests
# ============================================================================

test_build_tool_config_basic() {
    declare -A raw=(
        [target]="/home/user/.gitconfig"
        [merge_hook]="builtin:symlink"
    )
    declare -A config

    config_build_tool_config raw config "/tools/git"
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "git" "$(tool_config_get_tool_name config)" "tool_name from dir basename"
    assert_equals "/home/user/.gitconfig" "$(tool_config_get_target config)" "target"
    assert_equals "builtin:symlink" "$(tool_config_get_merge_hook config)" "merge_hook"
}

test_build_tool_config_with_layers() {
    declare -A raw=(
        [target]="~/.gitconfig"
        [merge_hook]="builtin:symlink"
        [layers_base]="local:configs/git"
        [layers_stripe]="STRIPE_DOTFILES:git"
    )
    declare -A config

    config_build_tool_config raw config "/tools/git"
    local rc=$?

    assert_equals "$E_OK" "$rc" "should return E_OK"
    assert_equals "2" "$(tool_config_get_layer_count config)" "should have 2 layers"
}

test_build_tool_config_with_install_hook() {
    declare -A raw=(
        [target]="/home/user/.gitconfig"
        [merge_hook]="builtin:symlink"
        [install_hook]="./install.sh"
    )
    declare -A config

    config_build_tool_config raw config "/tools/git"

    assert_equals "/tools/git/install.sh" "$(tool_config_get_install_hook config)" \
        "install_hook should be resolved"
}

test_build_tool_config_resolves_relative_merge_hook() {
    declare -A raw=(
        [target]="/home/user/.gitconfig"
        [merge_hook]="./merge.sh"
    )
    declare -A config

    config_build_tool_config raw config "/tools/git"

    assert_equals "/tools/git/merge.sh" "$(tool_config_get_merge_hook config)" \
        "merge_hook relative path resolved"
}

test_build_tool_config_missing_target() {
    declare -A raw=(
        [merge_hook]="builtin:symlink"
    )
    declare -A config

    local rc=0
    config_build_tool_config raw config "/tools/git" 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing target should fail validation"
}

test_build_tool_config_missing_merge_hook() {
    declare -A raw=(
        [target]="/home/user/.gitconfig"
    )
    declare -A config

    local rc=0
    config_build_tool_config raw config "/tools/git" 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "missing merge_hook should fail validation"
}

test_build_tool_config_invalid_layer_spec() {
    declare -A raw=(
        [target]="/home/user/.gitconfig"
        [merge_hook]="builtin:symlink"
        [layers_base]="invalid_no_colon"
    )
    declare -A config

    local rc=0
    config_build_tool_config raw config "/tools/git" 2>/dev/null || rc=$?

    assert_equals "$E_VALIDATION" "$rc" "invalid layer spec should fail"
}

test_build_tool_config_extracts_tool_name_from_path() {
    declare -A raw=(
        [target]="/home/user/.config/nvim"
        [merge_hook]="builtin:copy"
    )
    declare -A config

    config_build_tool_config raw config "/path/to/tools/nvim"

    assert_equals "nvim" "$(tool_config_get_tool_name config)" "tool_name from nested path"
}

test_build_tool_config_layer_values() {
    declare -A raw=(
        [target]="~/.gitconfig"
        [merge_hook]="builtin:symlink"
        [layers_base]="local:configs/git"
    )
    declare -A config

    config_build_tool_config raw config "/tools/git"

    # Find the layer (order not guaranteed due to associative array iteration)
    local found=0
    local count
    count=$(tool_config_get_layer_count config)
    for ((i = 0; i < count; i++)); do
        local name
        name=$(tool_config_get_layer_name config $i)
        if [[ "$name" == "base" ]]; then
            assert_equals "local" "$(tool_config_get_layer_source config $i)" "layer source"
            assert_equals "configs/git" "$(tool_config_get_layer_path config $i)" "layer path"
            found=1
            break
        fi
    done

    assert_equals "1" "$found" "base layer should exist"
}

# ============================================================================
# Run Tests
# ============================================================================

# Layer spec parsing
test_parse_layer_spec_local
test_parse_layer_spec_external
test_parse_layer_spec_nested_path
test_parse_layer_spec_invalid_no_colon
test_parse_layer_spec_invalid_empty_source
test_parse_layer_spec_invalid_empty_path

# Hook path resolution
test_resolve_hook_path_builtin
test_resolve_hook_path_builtin_concat
test_resolve_hook_path_relative_dotslash
test_resolve_hook_path_relative_plain
test_resolve_hook_path_absolute

# Full config building
test_build_tool_config_basic
test_build_tool_config_with_layers
test_build_tool_config_with_install_hook
test_build_tool_config_resolves_relative_merge_hook
test_build_tool_config_missing_target
test_build_tool_config_missing_merge_hook
test_build_tool_config_invalid_layer_spec
test_build_tool_config_extracts_tool_name_from_path
test_build_tool_config_layer_values

print_summary
