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
        log_skip "Homebrew install (non-macOS)"
        return 0
    fi

    if ! command -v brew &>/dev/null; then
        log_error "Homebrew not found"
        return 1
    fi

    if brew list "$package" &>/dev/null; then
        log_ok "$package already installed (Homebrew)"
        return 0
    fi

    log_step "Installing $package via Homebrew..."
    brew install "$package"
}

# Install via apt
# Usage: builtin_install_apt "package-name"
builtin_install_apt() {
    local package="$1"

    if [[ "$OS" != "linux" ]]; then
        log_skip "apt install (non-Linux)"
        return 0
    fi

    if ! command -v apt &>/dev/null; then
        log_error "apt not found"
        return 1
    fi

    if dpkg -l "$package" &>/dev/null 2>&1; then
        log_ok "$package already installed (apt)"
        return 0
    fi

    log_step "Installing $package via apt..."
    sudo apt update && sudo apt install -y "$package"
}

# Skip installation (assume tool is already available)
builtin_install_skip() {
    log_skip "Installation (builtin:skip)"
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
            log_error "Unknown built-in install hook: $builtin_name"
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
        log_ok "Symlinked: $TARGET"
        log_detail "-> $last_layer"
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
            log_ok "Symlinked: $TARGET"
            log_detail "-> $config_file"
        else
            log_error "Could not find config file in layer: $last_layer"
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
            log_detail "Appended: $layer_name"
        else
            log_warn "No config file in layer: $layer_path"
        fi
    done

    log_ok "Concatenated config written: $TARGET"
}

# JSON merge strategy: deep merge JSON files with jq
# Usage: builtin_merge_json
# Expects: LAYER_PATHS, TARGET environment variables
builtin_merge_json() {
    if ! command -v jq &>/dev/null; then
        log_error "jq is required for JSON merging but not found"
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
            log_detail "Merged: $config_file"
        fi
    done

    # Write merged JSON
    echo "$merged" | jq '.' > "$TARGET"
    log_ok "Merged JSON written: $TARGET"
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
            log_detail "Added source: $layer_name"
        fi
    done

    chmod +x "$TARGET"
    log_ok "Source config written: $TARGET"
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
            log_error "Unknown built-in merge hook: $builtin_name"
            return 1
            ;;
    esac
}
