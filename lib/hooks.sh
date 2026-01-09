#!/usr/bin/env bash
# lib/hooks.sh
# Invoke install and merge hooks with correct environment

set -euo pipefail

# Detect the current operating system
detect_os() {
    case "$(uname -s)" in
        Darwin)
            echo "darwin"
            ;;
        Linux)
            echo "linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Build the environment variables for hook execution
# Usage: build_hook_env "nvim" "base:work" "/path/base:/path/work" "/target" "/dotfiles" "work-mac"
# Returns: Exports environment variables
build_hook_env() {
    local tool="$1"
    local layers="$2"
    local layer_paths="$3"
    local target="$4"
    local dotfiles_dir="$5"
    local machine="$6"

    export TOOL="$tool"
    export LAYERS="$layers"
    export LAYER_PATHS="$layer_paths"
    export TARGET="$target"
    export DOTFILES_DIR="$dotfiles_dir"
    export MACHINE="$machine"
    export OS
    OS=$(detect_os)

    # Export custom env vars from tool context
    # Uses the new ctx_env_keys() accessor for cleaner iteration
    for key in $(ctx_env_keys); do
        local value
        value=$(ctx_get_env "$key")
        export "$key"="$value"
    done
}

# Clear hook environment variables
clear_hook_env() {
    unset TOOL LAYERS LAYER_PATHS TARGET DOTFILES_DIR MACHINE OS

    # Clear custom env vars using context accessor
    for key in $(ctx_env_keys); do
        unset "$key"
    done
}

# Resolve a hook specification to an executable path or builtin name
# Usage: resolve_hook "./install.sh" "/path/to/tools/nvim"
# Returns: "builtin:name" or absolute path
resolve_hook() {
    local hook_spec="$1"
    local tool_dir="$2"

    if [[ "$hook_spec" == builtin:* ]]; then
        # Built-in hook
        echo "$hook_spec"
    elif [[ "$hook_spec" == ./* ]]; then
        # Relative path - resolve against tool directory
        echo "${tool_dir}/${hook_spec#./}"
    elif [[ "$hook_spec" == /* ]]; then
        # Absolute path
        echo "$hook_spec"
    else
        # Treat as relative
        echo "${tool_dir}/${hook_spec}"
    fi
}

# Run an install hook
# Usage: run_install_hook "nvim" "/path/to/dotfiles" "base:work" "/path/base:/path/work" "work-mac"
run_install_hook() {
    local tool="$1"
    local dotfiles_dir="$2"
    local layers="$3"
    local layer_paths="$4"
    local machine="$5"

    local tool_dir="${dotfiles_dir}/tools/${tool}"
    local tool_conf="${tool_dir}/tool.conf"

    # Parse tool.conf - populates TOOL_CTX
    parse_tool_conf "$tool_conf"

    # Get values from context
    local install_hook
    install_hook=$(ctx_get "install_hook")

    # Skip if no install hook defined
    if [[ -z "$install_hook" ]]; then
        echo "[INFO] No install hook defined, skipping installation"
        return 0
    fi

    local hook
    hook=$(resolve_hook "$install_hook" "$tool_dir")

    # Build environment using context
    local target
    target=$(ctx_get "target")
    build_hook_env "$tool" "$layers" "$layer_paths" "$target" "$dotfiles_dir" "$machine"

    echo "==> Running install hook: $install_hook"

    if [[ "$hook" == builtin:* ]]; then
        local builtin_name="${hook#builtin:}"
        run_builtin_install "$builtin_name" "$tool"
    else
        if [[ ! -x "$hook" ]]; then
            chmod +x "$hook"
        fi
        "$hook"
    fi

    local exit_code=$?
    clear_hook_env
    return $exit_code
}

# Run a merge hook
# Usage: run_merge_hook "nvim" "/path/to/dotfiles" "base:work" "/path/base:/path/work" "work-mac"
run_merge_hook() {
    local tool="$1"
    local dotfiles_dir="$2"
    local layers="$3"
    local layer_paths="$4"
    local machine="$5"

    local tool_dir="${dotfiles_dir}/tools/${tool}"
    local tool_conf="${tool_dir}/tool.conf"

    # Parse tool.conf - populates TOOL_CTX
    parse_tool_conf "$tool_conf"

    # Get values from context
    local merge_hook
    merge_hook=$(ctx_get "merge_hook")

    # Merge hook is required
    if [[ -z "$merge_hook" ]]; then
        echo "[ERROR] No merge hook defined for: $tool" >&2
        return 1
    fi

    local hook
    hook=$(resolve_hook "$merge_hook" "$tool_dir")

    # Build environment using context
    local target
    target=$(ctx_get "target")
    build_hook_env "$tool" "$layers" "$layer_paths" "$target" "$dotfiles_dir" "$machine"

    # Handle broken symlinks at target (symlink exists but points to nothing)
    if [[ -L "$TARGET" && ! -e "$TARGET" ]]; then
        echo "[WARN] Removing broken symlink: $TARGET" >&2
        rm -f "$TARGET"
    fi

    echo "==> Running merge hook: $merge_hook"

    if [[ "$hook" == builtin:* ]]; then
        local builtin_name="${hook#builtin:}"
        run_builtin_merge "$builtin_name"
    else
        if [[ ! -x "$hook" ]]; then
            chmod +x "$hook"
        fi
        "$hook"
    fi

    local exit_code=$?
    clear_hook_env
    return $exit_code
}

# ============================================================================
# Tool Processing - Modular Functions
# ============================================================================

# Validate that a tool configuration exists
# Usage: validate_tool_config "nvim" "/path/to/dotfiles"
# Returns: 0 if valid, 1 if invalid
validate_tool_config() {
    local tool="$1"
    local dotfiles_dir="$2"
    local tool_conf="${dotfiles_dir}/tools/${tool}/tool.conf"

    if [[ ! -f "$tool_conf" ]]; then
        echo "[ERROR] No tool.conf found: $tool_conf" >&2
        return 1
    fi
    return 0
}

# Resolve layers for a tool and ensure external repos exist
# Usage: resolve_tool_layers "nvim" "/path/to/dotfiles"
# Returns: Sets RESOLVED_LAYERS and RESOLVED_LAYER_PATHS variables
# Outputs: Layer names (stdout for capture)
resolve_tool_layers() {
    local tool="$1"
    local dotfiles_dir="$2"

    # Get layer names from machine profile
    local layers
    layers=$(get_tool_layers "$tool")

    # Ensure external repos exist for these layers
    ensure_repos_for_layers "$layers" "$dotfiles_dir" "$tool"

    # Resolve layer paths to absolute paths
    local layer_paths
    layer_paths=$(resolve_layers "$tool" "$layers" "$dotfiles_dir")

    # Set for caller to use
    RESOLVED_LAYERS="$layers"
    RESOLVED_LAYER_PATHS="$layer_paths"
}

# Execute install and merge hooks for a tool
# Usage: execute_tool_hooks "nvim" "/path/to/dotfiles" "base:work" "/path1:/path2" "machine"
# Returns: 0 on success, 1 on failure
execute_tool_hooks() {
    local tool="$1"
    local dotfiles_dir="$2"
    local layers="$3"
    local layer_paths="$4"
    local machine="$5"

    # Run install hook
    if ! run_install_hook "$tool" "$dotfiles_dir" "$layers" "$layer_paths" "$machine"; then
        echo "[ERROR] Install hook failed for: $tool" >&2
        return 1
    fi

    # Run merge hook
    if ! run_merge_hook "$tool" "$dotfiles_dir" "$layers" "$layer_paths" "$machine"; then
        echo "[ERROR] Merge hook failed for: $tool" >&2
        return 1
    fi

    return 0
}

# Print layer information for debugging/logging
# Usage: print_layer_info "base:work" "/path1:/path2"
print_layer_info() {
    local layers="$1"
    local layer_paths="$2"

    echo "[INFO] Layers: $layers"
    echo "[INFO] Layer paths:"
    IFS=':' read -ra paths <<< "$layer_paths"
    for path in "${paths[@]}"; do
        echo "       - $path"
    done
}

# ============================================================================
# Main Tool Processing Entry Point
# ============================================================================

# Process a single tool: validate, resolve layers, run install, run merge
# This is the main entry point that orchestrates the modular functions above
# Usage: process_tool "nvim" "/path/to/dotfiles" "work-mac"
process_tool() {
    local tool="$1"
    local dotfiles_dir="$2"
    local machine="$3"

    echo ""
    echo "==> Processing: $tool"

    # Step 1: Validate tool configuration
    if ! validate_tool_config "$tool" "$dotfiles_dir"; then
        return 1
    fi

    # Step 2: Resolve layers and ensure repos exist
    # Sets RESOLVED_LAYERS and RESOLVED_LAYER_PATHS
    resolve_tool_layers "$tool" "$dotfiles_dir"

    # Step 3: Print layer information
    print_layer_info "$RESOLVED_LAYERS" "$RESOLVED_LAYER_PATHS"

    # Step 4: Execute hooks
    if ! execute_tool_hooks "$tool" "$dotfiles_dir" "$RESOLVED_LAYERS" "$RESOLVED_LAYER_PATHS" "$machine"; then
        return 1
    fi

    echo "[OK] $tool configured successfully"
}
