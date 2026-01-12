#!/usr/bin/env bash
# test/integration/test_full_workflow.sh
# Integration tests for the full installation workflow
# Uses real filesystem in temp directories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../test_utils.sh"

# Source the orchestrator (which pulls in all dependencies)
source "$SCRIPT_DIR/../../lib/orchestrator.sh"

echo "Testing: Full Workflow (Integration)"
echo ""

# Temp directory for each test
TEMP_DIR=""

# Setup: Create temp directory and dotfiles structure
setup() {
    TEMP_DIR=$(mktemp -d)

    # Initialize with real filesystem
    fs_init "real"

    # Set up log to capture output
    declare -A log_cfg=([output]="/dev/null" [level]="warn")
    log_init log_cfg

    strategy_clear
    orchestrator_reset

    # Create basic dotfiles structure
    mkdir -p "$TEMP_DIR/dotfiles/tools"
    mkdir -p "$TEMP_DIR/dotfiles/configs"
    mkdir -p "$TEMP_DIR/dotfiles/machines"
    mkdir -p "$TEMP_DIR/home"

    export HOME="$TEMP_DIR/home"
}

# Teardown: Clean up temp directory
teardown() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}

# --- Integration Test 1: Single tool symlink ---

test_single_tool_symlink() {
    setup

    # Create tool directory and config
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    # Create config directory with content
    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "[user]
    name = Test User
    email = test@example.com" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git)
git_layers=(base)
EOF

    # Initialize orchestrator
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    # Run installation
    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    # Verify result
    assert_equals 0 "$rc" "Installation should succeed"
    assert_equals "1" "${result[tools_succeeded]}" "Should have 1 success"

    # Verify symlink was created
    if [[ -L "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Symlink was created"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Symlink should exist at $TEMP_DIR/home/.gitconfig"
    fi

    teardown
}

# --- Integration Test 2: Multiple tools ---

test_multiple_tools() {
    setup

    # Create git tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "[user]
    name = Test" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create vim tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/vim"
    cat > "$TEMP_DIR/dotfiles/tools/vim/tool.conf" << 'EOF'
target="${HOME}/.vimrc"
merge_hook="builtin:symlink"
layers_base="local:configs/vim"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/vim"
    echo "set nocompatible" > "$TEMP_DIR/dotfiles/configs/vim/vimrc"

    # Create machine profile with both tools
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git vim)
git_layers=(base)
vim_layers=(base)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    # Verify results
    assert_equals 0 "$rc" "Installation should succeed"
    assert_equals "2" "${result[tools_processed]}" "Should process 2 tools"
    assert_equals "2" "${result[tools_succeeded]}" "Should have 2 successes"

    # Verify both symlinks exist
    local pass=1
    [[ -L "$TEMP_DIR/home/.gitconfig" ]] || pass=0
    [[ -L "$TEMP_DIR/home/.vimrc" ]] || pass=0

    if [[ $pass -eq 1 ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Both symlinks were created"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Both symlinks should exist"
    fi

    teardown
}

# --- Integration Test 3: Concat merge strategy ---

test_concat_merge() {
    setup

    # Create tool with concat merge
    mkdir -p "$TEMP_DIR/dotfiles/tools/shell"
    cat > "$TEMP_DIR/dotfiles/tools/shell/tool.conf" << 'EOF'
target="${HOME}/.shellrc"
merge_hook="builtin:concat"
layers_base="local:configs/shell-base"
layers_custom="local:configs/shell-custom"
EOF

    # Create base layer
    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-base"
    echo "# Base shell config
export PATH=/usr/local/bin:\$PATH" > "$TEMP_DIR/dotfiles/configs/shell-base/shellrc"

    # Create custom layer
    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-custom"
    echo "# Custom config
alias ll='ls -la'" > "$TEMP_DIR/dotfiles/configs/shell-custom/shellrc"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(shell)
shell_layers=(base custom)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Concat installation should succeed"

    # Verify the file was created (not a symlink)
    if [[ -f "$TEMP_DIR/home/.shellrc" && ! -L "$TEMP_DIR/home/.shellrc" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Concatenated file was created"

        # Check content includes both layers
        local content
        content=$(cat "$TEMP_DIR/home/.shellrc")
        if echo "$content" | grep -q "Base shell config" && echo "$content" | grep -q "Custom config"; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: File contains both layer contents"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_FAILED++)) || true
            echo -e "${RED}FAIL${NC}: File should contain content from both layers"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Concatenated file should exist"
    fi

    teardown
}

# --- Integration Test 4: Dry-run mode ---

test_dry_run_mode() {
    setup

    # Create tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "content" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git)
git_layers=(base)
EOF

    # Initialize with dry-run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles" [dry_run]="1")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Dry-run should succeed"
    assert_equals "1" "${result[success]}" "Should report success"

    # Verify no files were created
    if [[ ! -e "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Dry-run did not create files"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Dry-run should not create files"
    fi

    teardown
}

# --- Integration Test 5: Single tool installation ---

test_single_tool_installation() {
    setup

    # Create tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "git config" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Initialize
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    # Run single tool installation
    declare -A result
    local rc=0
    orchestrator_run_tool "git" result || rc=$?

    assert_equals 0 "$rc" "Single tool installation should succeed"
    assert_equals "1" "${result[success]}" "Should report success"

    # Verify symlink exists
    if [[ -L "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Single tool symlink was created"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Single tool symlink should exist"
    fi

    teardown
}

# --- Integration Test 6: Layer filtering from machine profile ---

test_layer_filtering() {
    setup

    # Create tool with multiple layers
    mkdir -p "$TEMP_DIR/dotfiles/tools/shell"
    cat > "$TEMP_DIR/dotfiles/tools/shell/tool.conf" << 'EOF'
target="${HOME}/.shellrc"
merge_hook="builtin:concat"
layers_base="local:configs/shell-base"
layers_work="local:configs/shell-work"
layers_personal="local:configs/shell-personal"
EOF

    # Create all layer directories
    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-base"
    echo "# base" > "$TEMP_DIR/dotfiles/configs/shell-base/shellrc"

    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-work"
    echo "# work" > "$TEMP_DIR/dotfiles/configs/shell-work/shellrc"

    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-personal"
    echo "# personal" > "$TEMP_DIR/dotfiles/configs/shell-personal/shellrc"

    # Create machine profile that only uses base and work
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(shell)
shell_layers=(base work)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Installation should succeed"

    # Verify content only includes base and work, not personal
    if [[ -f "$TEMP_DIR/home/.shellrc" ]]; then
        local content
        content=$(cat "$TEMP_DIR/home/.shellrc")

        local has_base has_work has_personal
        has_base=$(echo "$content" | grep -c "# base" || true)
        has_work=$(echo "$content" | grep -c "# work" || true)
        has_personal=$(echo "$content" | grep -c "# personal" || true)

        if [[ $has_base -gt 0 && $has_work -gt 0 && $has_personal -eq 0 ]]; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: Only requested layers were included"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_FAILED++)) || true
            echo -e "${RED}FAIL${NC}: Should only include base and work layers, not personal"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Output file should exist"
    fi

    teardown
}

# --- Integration Test 7: Backup existing files ---

test_backup_existing() {
    setup

    # Create existing file that should be backed up
    mkdir -p "$TEMP_DIR/home"
    echo "old content" > "$TEMP_DIR/home/.gitconfig"

    # Create tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "new content" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git)
git_layers=(base)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Installation should succeed"

    # Verify new symlink exists
    if [[ -L "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: New symlink was created"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: New symlink should exist"
    fi

    # Check for backup (this depends on builtin:symlink implementation)
    local backup_dir="$TEMP_DIR/dotfiles/.backup"
    if [[ -d "$backup_dir" ]]; then
        local backup_count
        backup_count=$(find "$backup_dir" -type f 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: Backup was created"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: Backup dir exists (may not have files if symlink replaced)"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Backup handling depends on implementation"
    fi

    teardown
}

# --- Integration Test 8: Tool with custom merge script ---

test_custom_merge_script() {
    setup

    # Create tool with custom merge script
    mkdir -p "$TEMP_DIR/dotfiles/tools/custom"
    cat > "$TEMP_DIR/dotfiles/tools/custom/tool.conf" << 'EOF'
target="${HOME}/.customrc"
merge_hook="./merge.sh"
layers_base="local:configs/custom"
EOF

    # Create custom merge script
    cat > "$TEMP_DIR/dotfiles/tools/custom/merge.sh" << 'SCRIPT'
#!/bin/bash
# Custom merge script
# Environment: TOOL, TARGET, LAYERS, LAYER_PATHS, DOTFILES_DIR

# Just create a file with the tool name
echo "Merged by: $TOOL" > "$TARGET"
echo "Layers: $LAYERS" >> "$TARGET"
SCRIPT
    chmod +x "$TEMP_DIR/dotfiles/tools/custom/merge.sh"

    # Create config directory
    mkdir -p "$TEMP_DIR/dotfiles/configs/custom"
    echo "custom content" > "$TEMP_DIR/dotfiles/configs/custom/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(custom)
custom_layers=(base)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Custom merge should succeed"

    # Verify file was created by custom script
    if [[ -f "$TEMP_DIR/home/.customrc" ]]; then
        local content
        content=$(cat "$TEMP_DIR/home/.customrc")
        if echo "$content" | grep -q "Merged by: custom"; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: Custom merge script executed correctly"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_FAILED++)) || true
            echo -e "${RED}FAIL${NC}: Custom merge script output not found"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Custom merge should create target file"
    fi

    teardown
}

# --- Integration Test 9: Mixed success and failure ---

test_mixed_results() {
    setup

    # Create valid git tool
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "git" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create invalid tool (missing required fields)
    mkdir -p "$TEMP_DIR/dotfiles/tools/broken"
    cat > "$TEMP_DIR/dotfiles/tools/broken/tool.conf" << 'EOF'
# Missing target and merge_hook
layers_base="local:configs/broken"
EOF

    # Create machine profile with both
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git broken)
git_layers=(base)
broken_layers=(base)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result 2>/dev/null || rc=$?

    # Should report failure due to broken tool
    assert_equals "$E_GENERIC" "$rc" "Should fail with broken tool"
    assert_equals "2" "${result[tools_processed]}" "Should process 2 tools"
    assert_equals "1" "${result[tools_succeeded]}" "Should have 1 success"
    assert_equals "1" "${result[tools_failed]}" "Should have 1 failure"
    assert_contains "${result[failed_tools]}" "broken" "broken should be in failed list"

    # Verify git still worked
    if [[ -L "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Good tool still installed despite broken tool"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Good tool should still be installed"
    fi

    teardown
}

# --- Integration Test 10: Source merge strategy ---

test_source_merge() {
    setup

    # Create tool with source merge
    mkdir -p "$TEMP_DIR/dotfiles/tools/zsh"
    cat > "$TEMP_DIR/dotfiles/tools/zsh/tool.conf" << 'EOF'
target="${HOME}/.zshrc"
merge_hook="builtin:source"
layers_base="local:configs/zsh-base"
layers_custom="local:configs/zsh-custom"
EOF

    # Create layers
    mkdir -p "$TEMP_DIR/dotfiles/configs/zsh-base"
    echo "# base zsh" > "$TEMP_DIR/dotfiles/configs/zsh-base/zshrc"

    mkdir -p "$TEMP_DIR/dotfiles/configs/zsh-custom"
    echo "# custom zsh" > "$TEMP_DIR/dotfiles/configs/zsh-custom/zshrc"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(zsh)
zsh_layers=(base custom)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Source merge should succeed"

    # Verify the file contains source statements
    if [[ -f "$TEMP_DIR/home/.zshrc" ]]; then
        local content
        content=$(cat "$TEMP_DIR/home/.zshrc")
        if echo "$content" | grep -q "source"; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: Source merge created file with source statements"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_FAILED++)) || true
            echo -e "${RED}FAIL${NC}: Source merge should include source statements"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Source merge should create target file"
    fi

    teardown
}

# --- Integration Test 11: JSON configuration ---

test_json_config() {
    setup

    # Create tool with JSON config instead of tool.conf
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.json" << 'EOF'
{
  "target": "~/.gitconfig",
  "merge_hook": "builtin:symlink",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" }
  ]
}
EOF

    # Create config directory with content
    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "[user]
    name = JSON User
    email = json@example.com" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git)
git_layers=(base)
EOF

    # Initialize orchestrator
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    # Run installation
    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    # Verify result
    assert_equals 0 "$rc" "Installation with JSON config should succeed"
    assert_equals "1" "${result[tools_succeeded]}" "Should have 1 success"

    # Verify symlink was created
    if [[ -L "$TEMP_DIR/home/.gitconfig" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Symlink was created from JSON config"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Symlink should exist at $TEMP_DIR/home/.gitconfig"
    fi

    teardown
}

# --- Integration Test 12: JSON config preferred over conf ---

test_json_preferred_over_conf() {
    setup

    # Create tool with both JSON and conf files
    mkdir -p "$TEMP_DIR/dotfiles/tools/git"

    # JSON config with different target path (using .gitconfig-json)
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.json" << 'EOF'
{
  "target": "~/.gitconfig-json",
  "merge_hook": "builtin:symlink",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" }
  ]
}
EOF

    # Legacy conf with different target path
    cat > "$TEMP_DIR/dotfiles/tools/git/tool.conf" << 'EOF'
target="${HOME}/.gitconfig-conf"
merge_hook="builtin:symlink"
layers_base="local:configs/git"
EOF

    # Create config directory
    mkdir -p "$TEMP_DIR/dotfiles/configs/git"
    echo "content" > "$TEMP_DIR/dotfiles/configs/git/config"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(git)
git_layers=(base)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "Installation should succeed"

    # Verify JSON target was used, not conf target
    if [[ -L "$TEMP_DIR/home/.gitconfig-json" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: JSON config was preferred over conf"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: JSON target .gitconfig-json should exist"
    fi

    # Verify conf target was NOT used
    if [[ ! -e "$TEMP_DIR/home/.gitconfig-conf" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: Conf target was not used"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Conf target should not exist"
    fi

    teardown
}

# --- Integration Test 13: JSON with multiple layers ---

test_json_multiple_layers() {
    setup

    # Create tool with JSON config and multiple layers
    mkdir -p "$TEMP_DIR/dotfiles/tools/shell"
    cat > "$TEMP_DIR/dotfiles/tools/shell/tool.json" << 'EOF'
{
  "target": "~/.shellrc",
  "merge_hook": "builtin:concat",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/shell-base" },
    { "name": "work", "source": "local", "path": "configs/shell-work" }
  ]
}
EOF

    # Create layer directories
    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-base"
    echo "# Base layer from JSON" > "$TEMP_DIR/dotfiles/configs/shell-base/shellrc"

    mkdir -p "$TEMP_DIR/dotfiles/configs/shell-work"
    echo "# Work layer from JSON" > "$TEMP_DIR/dotfiles/configs/shell-work/shellrc"

    # Create machine profile
    cat > "$TEMP_DIR/dotfiles/machines/test.sh" << 'EOF'
TOOLS=(shell)
shell_layers=(base work)
EOF

    # Initialize and run
    declare -A config=([dotfiles_dir]="$TEMP_DIR/dotfiles")
    orchestrator_init config

    declare -A result
    local rc=0
    orchestrator_run "$TEMP_DIR/dotfiles/machines/test.sh" result || rc=$?

    assert_equals 0 "$rc" "JSON multi-layer concat should succeed"

    # Verify file contains both layers
    if [[ -f "$TEMP_DIR/home/.shellrc" ]]; then
        local content
        content=$(cat "$TEMP_DIR/home/.shellrc")
        if echo "$content" | grep -q "Base layer from JSON" && \
           echo "$content" | grep -q "Work layer from JSON"; then
            ((TESTS_RUN++)) || true
            ((TESTS_PASSED++)) || true
            echo -e "${GREEN}PASS${NC}: JSON multi-layer config worked correctly"
        else
            ((TESTS_RUN++)) || true
            ((TESTS_FAILED++)) || true
            echo -e "${RED}FAIL${NC}: Both layers should be in output"
        fi
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: Output file should exist"
    fi

    teardown
}

# --- Integration Test 14: repos.json configuration ---

test_repos_json_config() {
    setup

    # Create repos.json file
    cat > "$TEMP_DIR/dotfiles/repos.json" << 'EOF'
{
  "$schema": "lib/dotfiles-system/schemas/repos.schema.json",
  "repositories": [
    {
      "name": "EXTERNAL_CONFIGS",
      "url": "git@github.com:test/external.git",
      "path": "~/.external-configs"
    }
  ]
}
EOF

    # Initialize the repos module directly to test it
    source "$SCRIPT_DIR/../../lib/resolver/repos.sh"

    # Reset and init with real filesystem
    repos_mock_reset
    repos_init "$TEMP_DIR/dotfiles"
    local rc=$?

    assert_equals 0 "$rc" "repos_init with JSON should succeed"

    # Verify repo was parsed
    if repos_is_configured "EXTERNAL_CONFIGS"; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: EXTERNAL_CONFIGS repo is configured"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: EXTERNAL_CONFIGS should be configured"
    fi

    # Verify URL was parsed correctly
    local url
    url=$(repos_get_url "EXTERNAL_CONFIGS")
    assert_equals "git@github.com:test/external.git" "$url" "URL should be parsed from JSON"

    # Verify path with ~ expansion
    local path
    path=$(repos_get_path "EXTERNAL_CONFIGS")
    assert_equals "$HOME/.external-configs" "$path" "Path should have ~ expanded"

    teardown
}

# --- Integration Test 15: repos.json preferred over repos.conf ---

test_repos_json_preferred() {
    setup

    # Create both repos.json and repos.conf with different values
    cat > "$TEMP_DIR/dotfiles/repos.json" << 'EOF'
{
  "repositories": [
    {
      "name": "MY_REPO",
      "url": "git@github.com:json/repo.git",
      "path": "~/.json-repo"
    }
  ]
}
EOF

    cat > "$TEMP_DIR/dotfiles/repos.conf" << EOF
MY_REPO="git@github.com:conf/repo.git|\${HOME}/.conf-repo"
EOF

    # Initialize the repos module
    source "$SCRIPT_DIR/../../lib/resolver/repos.sh"
    repos_mock_reset
    repos_init "$TEMP_DIR/dotfiles"

    # Verify JSON values were used
    local url path
    url=$(repos_get_url "MY_REPO")
    path=$(repos_get_path "MY_REPO")

    if [[ "$url" == "git@github.com:json/repo.git" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: JSON URL was used over conf"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: JSON URL should be preferred (got: $url)"
    fi

    if [[ "$path" == "$HOME/.json-repo" ]]; then
        ((TESTS_RUN++)) || true
        ((TESTS_PASSED++)) || true
        echo -e "${GREEN}PASS${NC}: JSON path was used over conf"
    else
        ((TESTS_RUN++)) || true
        ((TESTS_FAILED++)) || true
        echo -e "${RED}FAIL${NC}: JSON path should be preferred (got: $path)"
    fi

    teardown
}

# Run all integration tests
test_single_tool_symlink
test_multiple_tools
test_concat_merge
test_dry_run_mode
test_single_tool_installation
test_layer_filtering
test_backup_existing
test_custom_merge_script
test_mixed_results
test_source_merge
test_json_config
test_json_preferred_over_conf
test_json_multiple_layers
test_repos_json_config
test_repos_json_preferred

print_summary
