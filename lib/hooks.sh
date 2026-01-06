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

    # Export custom env vars from tool.conf
    for key in "${!TOOL_ENV[@]}"; do
        export "$key"="${TOOL_ENV[$key]}"
    done
}

# Clear hook environment variables
clear_hook_env() {
    unset TOOL LAYERS LAYER_PATHS TARGET DOTFILES_DIR MACHINE OS

    # Clear custom env vars
    for key in "${!TOOL_ENV[@]}"; do
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

    # Parse tool.conf if not already parsed
    parse_tool_conf "$tool_conf"

    # Skip if no install hook defined
    if [[ -z "${TOOL_INSTALL_HOOK:-}" ]]; then
        echo "[INFO] No install hook defined, skipping installation"
        return 0
    fi

    local hook
    hook=$(resolve_hook "$TOOL_INSTALL_HOOK" "$tool_dir")

    # Build environment
    build_hook_env "$tool" "$layers" "$layer_paths" "$TOOL_TARGET" "$dotfiles_dir" "$machine"

    echo "==> Running install hook: $TOOL_INSTALL_HOOK"

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

    # Parse tool.conf if not already parsed
    parse_tool_conf "$tool_conf"

    # Merge hook is required
    if [[ -z "${TOOL_MERGE_HOOK:-}" ]]; then
        echo "[ERROR] No merge hook defined for: $tool" >&2
        return 1
    fi

    local hook
    hook=$(resolve_hook "$TOOL_MERGE_HOOK" "$tool_dir")

    # Build environment
    build_hook_env "$tool" "$layers" "$layer_paths" "$TOOL_TARGET" "$dotfiles_dir" "$machine"

    echo "==> Running merge hook: $TOOL_MERGE_HOOK"

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

# Process a single tool: resolve layers, run install, run merge
# Usage: process_tool "nvim" "/path/to/dotfiles" "work-mac"
process_tool() {
    local tool="$1"
    local dotfiles_dir="$2"
    local machine="$3"

    echo ""
    echo "==> Processing: $tool"

    local tool_conf="${dotfiles_dir}/tools/${tool}/tool.conf"

    if [[ ! -f "$tool_conf" ]]; then
        echo "[ERROR] No tool.conf found: $tool_conf" >&2
        return 1
    fi

    # Get layer names from machine profile
    local layers
    layers=$(get_tool_layers "$tool")

    echo "[INFO] Layers: $layers"

    # Ensure external repos exist
    ensure_repos_for_layers "$layers" "$dotfiles_dir" "$tool"

    # Resolve layer paths
    local layer_paths
    layer_paths=$(resolve_layers "$tool" "$layers" "$dotfiles_dir")

    echo "[INFO] Layer paths:"
    IFS=':' read -ra paths <<< "$layer_paths"
    for path in "${paths[@]}"; do
        echo "       - $path"
    done

    # Run install hook
    run_install_hook "$tool" "$dotfiles_dir" "$layers" "$layer_paths" "$machine" || {
        echo "[ERROR] Install hook failed for: $tool" >&2
        return 1
    }

    # Run merge hook
    run_merge_hook "$tool" "$dotfiles_dir" "$layers" "$layer_paths" "$machine" || {
        echo "[ERROR] Merge hook failed for: $tool" >&2
        return 1
    }

    echo "[OK] $tool configured successfully"
}
