#!/usr/bin/env bash
# lib/builtins.sh
# Built-in install and merge hooks

set -euo pipefail

# Source utilities for safe operations
source "${BASH_SOURCE%/*}/utils.sh"

# ============================================================================
# Built-in Install Hooks
# ============================================================================

# Install via Homebrew
# Usage: builtin_install_homebrew "package-name"
builtin_install_homebrew() {
    local package="$1"

    if [[ "$OS" != "darwin" ]]; then
        echo "[WARN] Homebrew install skipped on non-macOS" >&2
        return 0
    fi

    if ! command -v brew &>/dev/null; then
        echo "[ERROR] Homebrew not found" >&2
        return 1
    fi

    if brew list "$package" &>/dev/null; then
        echo "[INFO] $package already installed via Homebrew"
        return 0
    fi

    echo "[INFO] Installing $package via Homebrew..."
    brew install "$package"
}

# Install via apt
# Usage: builtin_install_apt "package-name"
builtin_install_apt() {
    local package="$1"

    if [[ "$OS" != "linux" ]]; then
        echo "[WARN] apt install skipped on non-Linux" >&2
        return 0
    fi

    if ! command -v apt &>/dev/null; then
        echo "[ERROR] apt not found" >&2
        return 1
    fi

    if dpkg -l "$package" &>/dev/null 2>&1; then
        echo "[INFO] $package already installed via apt"
        return 0
    fi

    echo "[INFO] Installing $package via apt..."
    sudo apt update && sudo apt install -y "$package"
}

# Skip installation (assume tool is already available)
builtin_install_skip() {
    echo "[INFO] Skipping installation (builtin:skip)"
    return 0
}

# Dispatch to the appropriate built-in install hook
# Usage: run_builtin_install "homebrew" "nvim"
run_builtin_install() {
    local builtin_name="$1"
    local tool="$2"

    case "$builtin_name" in
        homebrew)
            builtin_install_homebrew "$tool"
            ;;
        apt)
            builtin_install_apt "$tool"
            ;;
        skip)
            builtin_install_skip
            ;;
        *)
            echo "[ERROR] Unknown built-in install hook: $builtin_name" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# Built-in Merge Hooks
# ============================================================================

# Symlink strategy: symlink last layer to target (simple override)
# Usage: builtin_merge_symlink
# Expects: LAYER_PATHS, TARGET environment variables
builtin_merge_symlink() {
    IFS=':' read -ra paths <<< "$LAYER_PATHS"

    # Use the last layer (highest priority)
    local last_layer="${paths[-1]}"

    # Determine if target is a file or directory based on layer content
    if [[ -d "$last_layer" ]]; then
        # Layer is a directory - symlink the directory
        local target_parent
        target_parent=$(dirname "$TARGET")
        mkdir -p "$target_parent"

        # Remove existing target (with backup)
        safe_remove_rf "$TARGET"

        # Create symlink
        ln -sf "$last_layer" "$TARGET"
        echo "[INFO] Symlinked directory: $TARGET -> $last_layer"
    else
        # Layer is a file - symlink the file
        local target_parent
        target_parent=$(dirname "$TARGET")
        mkdir -p "$target_parent"

        # Remove existing target (with backup)
        safe_remove "$TARGET"

        # Find the config file in the layer using shared utility
        local config_file
        local target_name
        target_name=$(basename "$TARGET")
        config_file=$(find_config_file "$last_layer" "$target_name") || true

        if [[ -n "$config_file" ]]; then
            ln -sf "$config_file" "$TARGET"
            echo "[INFO] Symlinked file: $TARGET -> $config_file"
        else
            echo "[ERROR] Could not find config file in layer: $last_layer" >&2
            return 1
        fi
    fi
}

# Concatenate strategy: concatenate all layers into single file
# Usage: builtin_merge_concat
# Expects: LAYERS, LAYER_PATHS, TARGET environment variables
builtin_merge_concat() {
    IFS=':' read -ra layer_names <<< "$LAYERS"
    IFS=':' read -ra paths <<< "$LAYER_PATHS"

    local target_parent
    target_parent=$(dirname "$TARGET")
    mkdir -p "$target_parent"

    # Remove existing file/symlink (with backup) and create fresh
    safe_remove "$TARGET"
    touch "$TARGET"

    local target_name
    target_name=$(basename "$TARGET")

    for i in "${!paths[@]}"; do
        local layer_path="${paths[$i]}"
        local layer_name="${layer_names[$i]}"

        # Find the config file in this layer using shared utility
        local config_file
        config_file=$(find_config_file "$layer_path" "$target_name") || true

        if [[ -n "$config_file" && -f "$config_file" ]]; then
            echo "# === Layer: $layer_name ===" >> "$TARGET"
            echo "# Source: $config_file" >> "$TARGET"
            echo "" >> "$TARGET"
            cat "$config_file" >> "$TARGET"
            echo "" >> "$TARGET"
            echo "[INFO] Appended layer: $layer_name"
        else
            echo "[WARN] No config file found in layer: $layer_path" >&2
        fi
    done

    echo "[INFO] Concatenated config written to: $TARGET"
}

# JSON merge strategy: deep merge JSON files with jq
# Usage: builtin_merge_json
# Expects: LAYER_PATHS, TARGET environment variables
builtin_merge_json() {
    if ! command -v jq &>/dev/null; then
        echo "[ERROR] jq is required for JSON merging but not found" >&2
        return 1
    fi

    IFS=':' read -ra paths <<< "$LAYER_PATHS"

    local target_parent
    target_parent=$(dirname "$TARGET")
    mkdir -p "$target_parent"

    local target_name
    target_name=$(basename "$TARGET")

    # Start with empty object
    local merged="{}"

    for layer_path in "${paths[@]}"; do
        # Find JSON file in layer using shared utility
        local config_file
        config_file=$(find_config_file "$layer_path" "$target_name" "json") || true

        if [[ -n "$config_file" && -f "$config_file" ]]; then
            # Deep merge using jq
            merged=$(echo "$merged" | jq -s '.[0] * .[1]' - "$config_file")
            echo "[INFO] Merged JSON layer: $config_file"
        fi
    done

    # Write merged JSON
    echo "$merged" | jq '.' > "$TARGET"
    echo "[INFO] Merged JSON written to: $TARGET"
}

# Source strategy: generate a file that sources all layer files
# Usage: builtin_merge_source
# Expects: LAYERS, LAYER_PATHS, TARGET environment variables
builtin_merge_source() {
    IFS=':' read -ra layer_names <<< "$LAYERS"
    IFS=':' read -ra paths <<< "$LAYER_PATHS"

    local target_parent
    target_parent=$(dirname "$TARGET")
    mkdir -p "$target_parent"

    local target_name
    target_name=$(basename "$TARGET")

    # Start the target file
    cat > "$TARGET" << 'HEADER'
# Auto-generated by dotfiles layering system
# This file sources configs from multiple layers
HEADER

    for i in "${!paths[@]}"; do
        local layer_path="${paths[$i]}"
        local layer_name="${layer_names[$i]}"

        # Find the config file in this layer using shared utility
        local config_file
        config_file=$(find_config_file "$layer_path" "$target_name") || true

        if [[ -n "$config_file" && -f "$config_file" ]]; then
            echo "" >> "$TARGET"
            echo "# Layer: $layer_name" >> "$TARGET"
            echo "[ -f \"$config_file\" ] && source \"$config_file\"" >> "$TARGET"
            echo "[INFO] Added source for layer: $layer_name"
        fi
    done

    chmod +x "$TARGET"
    echo "[INFO] Source config written to: $TARGET"
}

# Dispatch to the appropriate built-in merge hook
# Usage: run_builtin_merge "symlink"
run_builtin_merge() {
    local builtin_name="$1"

    case "$builtin_name" in
        symlink)
            builtin_merge_symlink
            ;;
        concat)
            builtin_merge_concat
            ;;
        json-merge|json)
            builtin_merge_json
            ;;
        source)
            builtin_merge_source
            ;;
        *)
            echo "[ERROR] Unknown built-in merge hook: $builtin_name" >&2
            return 1
            ;;
    esac
}
