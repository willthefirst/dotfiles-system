#!/usr/bin/env bash
# test/integration/test_migrate_to_json.sh
# Integration tests for migration script with real config files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"

REAL_DOTFILES_DIR="${SCRIPT_DIR}/../../../.."
MIGRATE_SCRIPT="$REAL_DOTFILES_DIR/scripts/migrate-to-json.sh"

echo "Testing: migrate-to-json.sh (integration)"
echo ""

# ============================================================================
# Setup/Teardown
# ============================================================================

setup() {
    setup_test_env

    # Create complete test environment mirroring real dotfiles structure
    mkdir -p "$TEST_TEMP_DIR/tools/git"
    mkdir -p "$TEST_TEMP_DIR/tools/zsh"
    mkdir -p "$TEST_TEMP_DIR/tools/nvim"
    mkdir -p "$TEST_TEMP_DIR/machines"
    mkdir -p "$TEST_TEMP_DIR/lib/dotfiles-system/schemas"

    # Copy schemas (from real dotfiles dir)
    cp "$REAL_DOTFILES_DIR/lib/dotfiles-system/schemas/"*.json "$TEST_TEMP_DIR/lib/dotfiles-system/schemas/"

    # Create tool configs
    cat > "$TEST_TEMP_DIR/tools/git/tool.conf" <<'EOF'
# tools/git/tool.conf
layers_base="local:configs/git"
layers_stripe="STRIPE_DOTFILES:git"
target="${HOME}/.gitconfig"
install_hook="./install.sh"
merge_hook="./merge.sh"
EOF

    cat > "$TEST_TEMP_DIR/tools/zsh/tool.conf" <<'EOF'
layers_base="local:configs/zsh"
layers_stripe="STRIPE_DOTFILES:zsh"
layers_devbox="STRIPE_DOTFILES:zsh-devbox"
target="${HOME}/.zshrc"
merge_hook="builtin:source"
EOF

    cat > "$TEST_TEMP_DIR/tools/nvim/tool.conf" <<'EOF'
layers_base="local:configs/nvim"
target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
install_hook="./install.sh"
merge_hook="./merge.sh"
EOF

    # Create repos.conf
    cat > "$TEST_TEMP_DIR/repos.conf" <<'EOF'
# External repos
STRIPE_DOTFILES="git@git.corp.stripe.com:willm/dotfiles-stripe.git|${HOME}/.dotfiles-stripe"
EOF

    # Create machine profiles
    cat > "$TEST_TEMP_DIR/machines/personal-mac.sh" <<'EOF'
# machines/personal-mac.sh
# Personal Mac configuration - base layers only

TOOLS=(
    git
    zsh
    nvim
)

git_layers=(base)
zsh_layers=(base)
nvim_layers=(base)
EOF

    cat > "$TEST_TEMP_DIR/machines/work-mac.sh" <<'EOF'
# machines/work-mac.sh
# Work Mac configuration - base + stripe layers

TOOLS=(
    git
    zsh
    nvim
)

git_layers=(base stripe)
zsh_layers=(base stripe)
nvim_layers=(base stripe)
EOF

    export DOTFILES_DIR="$TEST_TEMP_DIR"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Full Migration Test
# ============================================================================

test_full_migration() {
    setup

    # Run full migration
    local output
    output=$("$MIGRATE_SCRIPT" 2>&1)
    local rc=$?

    assert_equals "0" "$rc" "full migration should succeed"

    # Verify all JSON files were created
    assert_file_exists "$TEST_TEMP_DIR/tools/git/tool.json" "git/tool.json should be created"
    assert_file_exists "$TEST_TEMP_DIR/tools/zsh/tool.json" "zsh/tool.json should be created"
    assert_file_exists "$TEST_TEMP_DIR/tools/nvim/tool.json" "nvim/tool.json should be created"
    assert_file_exists "$TEST_TEMP_DIR/repos.json" "repos.json should be created"
    assert_file_exists "$TEST_TEMP_DIR/machines/personal-mac.json" "personal-mac.json should be created"
    assert_file_exists "$TEST_TEMP_DIR/machines/work-mac.json" "work-mac.json should be created"

    teardown
}

test_migration_produces_valid_json() {
    setup

    "$MIGRATE_SCRIPT" 2>&1

    # Validate all JSON files with jq
    local valid=true
    for json_file in "$TEST_TEMP_DIR"/tools/*/tool.json "$TEST_TEMP_DIR/repos.json" "$TEST_TEMP_DIR"/machines/*.json; do
        if ! jq . "$json_file" &>/dev/null; then
            valid=false
            echo "Invalid JSON: $json_file"
        fi
    done

    if [[ "$valid" == "true" ]]; then
        assert_equals "0" "0" "all JSON files are valid"
    else
        assert_equals "0" "1" "some JSON files are invalid"
    fi

    teardown
}

test_migration_has_correct_schema_refs() {
    setup

    "$MIGRATE_SCRIPT" 2>&1

    # Check schema references
    local git_schema repos_schema machine_schema
    git_schema=$(jq -r '.["$schema"]' "$TEST_TEMP_DIR/tools/git/tool.json")
    repos_schema=$(jq -r '.["$schema"]' "$TEST_TEMP_DIR/repos.json")
    machine_schema=$(jq -r '.["$schema"]' "$TEST_TEMP_DIR/machines/personal-mac.json")

    assert_equals "../../lib/dotfiles-system/schemas/tool.schema.json" "$git_schema" "tool schema ref should be correct"
    assert_equals "lib/dotfiles-system/schemas/repos.schema.json" "$repos_schema" "repos schema ref should be correct"
    assert_equals "../lib/dotfiles-system/schemas/machine.schema.json" "$machine_schema" "machine schema ref should be correct"

    teardown
}

test_migration_preserves_all_tool_fields() {
    setup

    "$MIGRATE_SCRIPT" 2>&1

    # Verify git tool has all expected fields
    local has_target has_merge has_install has_layers has_schema
    has_target=$(jq 'has("target")' "$TEST_TEMP_DIR/tools/git/tool.json")
    has_merge=$(jq 'has("merge_hook")' "$TEST_TEMP_DIR/tools/git/tool.json")
    has_install=$(jq 'has("install_hook")' "$TEST_TEMP_DIR/tools/git/tool.json")
    has_layers=$(jq 'has("layers")' "$TEST_TEMP_DIR/tools/git/tool.json")
    has_schema=$(jq 'has("$schema")' "$TEST_TEMP_DIR/tools/git/tool.json")

    assert_equals "true" "$has_target" "tool should have target"
    assert_equals "true" "$has_merge" "tool should have merge_hook"
    assert_equals "true" "$has_install" "tool should have install_hook"
    assert_equals "true" "$has_layers" "tool should have layers"
    assert_equals "true" "$has_schema" "tool should have \$schema"

    teardown
}

test_migration_idempotent() {
    setup

    # Run migration twice
    "$MIGRATE_SCRIPT" 2>&1
    local first_run_git
    first_run_git=$(cat "$TEST_TEMP_DIR/tools/git/tool.json")

    "$MIGRATE_SCRIPT" 2>&1
    local second_run_git
    second_run_git=$(cat "$TEST_TEMP_DIR/tools/git/tool.json")

    # JSON should be identical (migration should skip existing)
    assert_equals "$first_run_git" "$second_run_git" "second run should not modify existing JSON"

    teardown
}

test_migration_tools_have_correct_layers() {
    setup

    "$MIGRATE_SCRIPT" 2>&1

    # zsh should have 3 layers: base, devbox, stripe (sorted alphabetically)
    local zsh_layers_count
    zsh_layers_count=$(jq '.layers | length' "$TEST_TEMP_DIR/tools/zsh/tool.json")
    assert_equals "3" "$zsh_layers_count" "zsh should have 3 layers"

    # Verify layer content
    local base_source stripe_path
    base_source=$(jq -r '.layers[] | select(.name=="base") | .source' "$TEST_TEMP_DIR/tools/zsh/tool.json")
    stripe_path=$(jq -r '.layers[] | select(.name=="stripe") | .path' "$TEST_TEMP_DIR/tools/zsh/tool.json")

    assert_equals "local" "$base_source" "base layer source should be local"
    assert_equals "zsh" "$stripe_path" "stripe layer path should be zsh"

    teardown
}

test_migration_machines_have_correct_tools() {
    setup

    "$MIGRATE_SCRIPT" 2>&1

    # work-mac should have stripe layers
    local work_git_layers work_zsh_first_layer work_zsh_second_layer
    work_git_layers=$(jq '.tools.git | length' "$TEST_TEMP_DIR/machines/work-mac.json")
    work_zsh_first_layer=$(jq -r '.tools.zsh[0]' "$TEST_TEMP_DIR/machines/work-mac.json")
    work_zsh_second_layer=$(jq -r '.tools.zsh[1]' "$TEST_TEMP_DIR/machines/work-mac.json")

    assert_equals "2" "$work_git_layers" "work-mac git should have 2 layers"
    assert_equals "base" "$work_zsh_first_layer" "work-mac zsh first layer should be base"
    assert_equals "stripe" "$work_zsh_second_layer" "work-mac zsh second layer should be stripe"

    # personal-mac should have base only
    local personal_git_layers
    personal_git_layers=$(jq '.tools.git | length' "$TEST_TEMP_DIR/machines/personal-mac.json")
    assert_equals "1" "$personal_git_layers" "personal-mac git should have 1 layer"

    teardown
}

# ============================================================================
# Run Tests
# ============================================================================

test_full_migration
test_migration_produces_valid_json
test_migration_has_correct_schema_refs
test_migration_preserves_all_tool_fields
test_migration_idempotent
test_migration_tools_have_correct_layers
test_migration_machines_have_correct_tools

print_summary
