#!/usr/bin/env bash
# test/unit/scripts/test_migrate_to_json.sh
# Unit tests for scripts/migrate-to-json.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../test_utils.sh"

REAL_DOTFILES_DIR="${SCRIPT_DIR}/../../../../.."
MIGRATE_SCRIPT="$REAL_DOTFILES_DIR/scripts/migrate-to-json.sh"

echo "Testing: scripts/migrate-to-json.sh"
echo ""

# ============================================================================
# Setup/Teardown
# ============================================================================

setup() {
    setup_test_env
    mkdir -p "$TEST_TEMP_DIR/tools/testgit"
    mkdir -p "$TEST_TEMP_DIR/machines"
    mkdir -p "$TEST_TEMP_DIR/lib/dotfiles-system/schemas"

    # Copy schemas to temp dir (from real dotfiles dir)
    cp "$REAL_DOTFILES_DIR/lib/dotfiles-system/schemas/"*.json "$TEST_TEMP_DIR/lib/dotfiles-system/schemas/"

    # Set DOTFILES_DIR to temp dir for tests
    export DOTFILES_DIR="$TEST_TEMP_DIR"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Tool Migration Tests
# ============================================================================

test_migrate_tool_conf_basic() {
    setup

    # Create a basic tool.conf
    cat > "$TEST_TEMP_DIR/tools/testgit/tool.conf" <<'EOF'
target="~/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    # Run migration
    local output
    output=$("$MIGRATE_SCRIPT" --tool testgit 2>&1)
    local rc=$?

    assert_equals "0" "$rc" "migration should succeed"
    assert_file_exists "$TEST_TEMP_DIR/tools/testgit/tool.json" "tool.json should be created"

    # Verify JSON content
    local target merge_hook layers_count
    target=$(jq -r '.target' "$TEST_TEMP_DIR/tools/testgit/tool.json")
    merge_hook=$(jq -r '.merge_hook' "$TEST_TEMP_DIR/tools/testgit/tool.json")
    layers_count=$(jq '.layers | length' "$TEST_TEMP_DIR/tools/testgit/tool.json")

    assert_equals "~/.gitconfig" "$target" "target should be ~/"
    assert_equals "builtin:symlink" "$merge_hook" "merge_hook should be set"
    assert_equals "1" "$layers_count" "should have 1 layer"

    teardown
}

test_migrate_tool_conf_multiple_layers() {
    setup

    # Create tool.conf with multiple layers
    cat > "$TEST_TEMP_DIR/tools/testgit/tool.conf" <<'EOF'
target="~/.gitconfig"
merge_hook="./merge.sh"
install_hook="./install.sh"
layers_base="local:configs/git"
layers_stripe="STRIPE_DOTFILES:git"
layers_personal="local:personal/git"
EOF

    "$MIGRATE_SCRIPT" --tool testgit 2>&1

    local layers_count install_hook
    layers_count=$(jq '.layers | length' "$TEST_TEMP_DIR/tools/testgit/tool.json")
    install_hook=$(jq -r '.install_hook' "$TEST_TEMP_DIR/tools/testgit/tool.json")

    assert_equals "3" "$layers_count" "should have 3 layers"
    assert_equals "./install.sh" "$install_hook" "install_hook should be set"

    # Verify layer order (alphabetical by name)
    local first_layer second_layer
    first_layer=$(jq -r '.layers[0].name' "$TEST_TEMP_DIR/tools/testgit/tool.json")
    second_layer=$(jq -r '.layers[1].name' "$TEST_TEMP_DIR/tools/testgit/tool.json")

    assert_equals "base" "$first_layer" "first layer should be base"
    assert_equals "personal" "$second_layer" "second layer should be personal"

    teardown
}

test_migrate_tool_conf_with_env_vars() {
    setup
    export HOME="/home/testuser"

    # Create tool.conf with environment variable
    cat > "$TEST_TEMP_DIR/tools/testgit/tool.conf" <<'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    "$MIGRATE_SCRIPT" --tool testgit 2>&1

    local target
    target=$(jq -r '.target' "$TEST_TEMP_DIR/tools/testgit/tool.json")

    assert_equals "~/.gitconfig" "$target" "HOME should be normalized to ~"

    teardown
}

test_migrate_tool_skips_existing_json() {
    setup

    # Create both tool.conf and tool.json
    cat > "$TEST_TEMP_DIR/tools/testgit/tool.conf" <<'EOF'
target="~/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    cat > "$TEST_TEMP_DIR/tools/testgit/tool.json" <<'EOF'
{"existing": "json"}
EOF

    local output
    output=$("$MIGRATE_SCRIPT" --tool testgit 2>&1)

    # Verify original JSON is preserved
    local existing
    existing=$(jq -r '.existing' "$TEST_TEMP_DIR/tools/testgit/tool.json")

    assert_equals "json" "$existing" "existing JSON should not be overwritten"
    assert_contains "$output" "already exists" "should log skip message"

    teardown
}

# ============================================================================
# Repos Migration Tests
# ============================================================================

test_migrate_repos_conf_basic() {
    setup

    # Create repos.conf
    cat > "$TEST_TEMP_DIR/repos.conf" <<'EOF'
# External repositories
STRIPE_DOTFILES="git@git.corp.stripe.com:willm/dotfiles.git|~/.dotfiles-stripe"
EOF

    "$MIGRATE_SCRIPT" --repos 2>&1

    assert_file_exists "$TEST_TEMP_DIR/repos.json" "repos.json should be created"

    local repo_name repo_url repo_path
    repo_name=$(jq -r '.repositories[0].name' "$TEST_TEMP_DIR/repos.json")
    repo_url=$(jq -r '.repositories[0].url' "$TEST_TEMP_DIR/repos.json")
    repo_path=$(jq -r '.repositories[0].path' "$TEST_TEMP_DIR/repos.json")

    assert_equals "STRIPE_DOTFILES" "$repo_name" "repo name should be set"
    assert_equals "git@git.corp.stripe.com:willm/dotfiles.git" "$repo_url" "repo URL should be set"
    assert_equals "~/.dotfiles-stripe" "$repo_path" "repo path should use ~"

    teardown
}

test_migrate_repos_conf_multiple_repos() {
    setup

    cat > "$TEST_TEMP_DIR/repos.conf" <<'EOF'
WORK_DOTFILES="git@github.com:work/dotfiles.git|~/.work-dotfiles"
PRIVATE_DOTFILES="git@github.com:user/private.git|~/.private-dotfiles"
EOF

    "$MIGRATE_SCRIPT" --repos 2>&1

    local count
    count=$(jq '.repositories | length' "$TEST_TEMP_DIR/repos.json")

    assert_equals "2" "$count" "should have 2 repositories"

    teardown
}

# ============================================================================
# Machine Profile Migration Tests
# ============================================================================

test_migrate_machine_profile_basic() {
    setup

    # Create machine profile
    cat > "$TEST_TEMP_DIR/machines/test-mac.sh" <<'EOF'
# machines/test-mac.sh
# Test Mac configuration

TOOLS=(
    git
    zsh
)

git_layers=(base)
zsh_layers=(base stripe)
EOF

    "$MIGRATE_SCRIPT" --machines 2>&1

    assert_file_exists "$TEST_TEMP_DIR/machines/test-mac.json" "machine JSON should be created"

    local name tools_count git_layers zsh_layers
    name=$(jq -r '.name' "$TEST_TEMP_DIR/machines/test-mac.json")
    tools_count=$(jq '.tools | keys | length' "$TEST_TEMP_DIR/machines/test-mac.json")
    git_layers=$(jq '.tools.git | length' "$TEST_TEMP_DIR/machines/test-mac.json")
    zsh_layers=$(jq '.tools.zsh | length' "$TEST_TEMP_DIR/machines/test-mac.json")

    assert_equals "test-mac" "$name" "name should match filename"
    assert_equals "2" "$tools_count" "should have 2 tools"
    assert_equals "1" "$git_layers" "git should have 1 layer"
    assert_equals "2" "$zsh_layers" "zsh should have 2 layers"

    teardown
}

test_migrate_machine_profile_preserves_layer_order() {
    setup

    cat > "$TEST_TEMP_DIR/machines/test-devbox.sh" <<'EOF'
TOOLS=(zsh)
zsh_layers=(base stripe devbox)
EOF

    "$MIGRATE_SCRIPT" --machines 2>&1

    local layer0 layer1 layer2
    layer0=$(jq -r '.tools.zsh[0]' "$TEST_TEMP_DIR/machines/test-devbox.json")
    layer1=$(jq -r '.tools.zsh[1]' "$TEST_TEMP_DIR/machines/test-devbox.json")
    layer2=$(jq -r '.tools.zsh[2]' "$TEST_TEMP_DIR/machines/test-devbox.json")

    assert_equals "base" "$layer0" "first layer should be base"
    assert_equals "stripe" "$layer1" "second layer should be stripe"
    assert_equals "devbox" "$layer2" "third layer should be devbox"

    teardown
}

# ============================================================================
# Dry Run Tests
# ============================================================================

test_dry_run_does_not_create_files() {
    setup

    cat > "$TEST_TEMP_DIR/tools/testgit/tool.conf" <<'EOF'
target="~/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    "$MIGRATE_SCRIPT" --dry-run --tool testgit 2>&1

    if [[ -f "$TEST_TEMP_DIR/tools/testgit/tool.json" ]]; then
        assert_equals "0" "1" "dry-run should not create files"
    else
        assert_equals "0" "0" "dry-run correctly did not create files"
    fi

    teardown
}

# ============================================================================
# Run Tests
# ============================================================================

test_migrate_tool_conf_basic
test_migrate_tool_conf_multiple_layers
test_migrate_tool_conf_with_env_vars
test_migrate_tool_skips_existing_json
test_migrate_repos_conf_basic
test_migrate_repos_conf_multiple_repos
test_migrate_machine_profile_basic
test_migrate_machine_profile_preserves_layer_order
test_dry_run_does_not_create_files

print_summary
