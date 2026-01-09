#!/usr/bin/env bash
# install.sh
# Main entry point for the dotfiles layering system
#
# This is the FRAMEWORK entry point. It sources user configuration from
# an external dotfiles repo (default: ~/.dotfiles).
#
# Usage: ./install.sh <machine-profile> [options]
#
# Example:
#   ./install.sh personal-mac
#   ./install.sh work-mac
#   ./install.sh work-mac --dotfiles ~/my-dotfiles

# Check bash version (4+ required for associative arrays and declare -g)
if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "Error: Bash 4+ required (found ${BASH_VERSION})" >&2
    echo "On macOS, install via: brew install bash" >&2
    echo "Then run: /opt/homebrew/bin/bash $0 $*" >&2
    exit 1
fi

set -euo pipefail

# Determine the framework directory (where this script lives)
FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default user dotfiles location
USER_DOTFILES="${HOME}/.dotfiles"

# ============================================================================
# Helper Functions
# ============================================================================

usage() {
    echo "Usage: $0 <machine-profile> [options]"
    echo ""
    echo "Machine profiles are defined in <dotfiles>/machines/<name>.sh"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -l, --list              List available machine profiles"
    echo "  -t, --tool TOOL         Only process a specific tool"
    echo "  -n, --dry-run           Show what would be done without making changes"
    echo "  -d, --dotfiles PATH     Path to user dotfiles (default: ~/.dotfiles)"
    echo ""
    echo "Examples:"
    echo "  $0 personal-mac"
    echo "  $0 stripe-mac --dotfiles ~/code/dotfiles-personal"
    echo "  $0 stripe-mac --tool nvim"
}

list_profiles() {
    echo "Available machine profiles:"
    if [[ -d "${USER_DOTFILES}/machines" ]]; then
        for profile in "${USER_DOTFILES}"/machines/*.sh; do
            if [[ -f "$profile" ]]; then
                local name
                name=$(basename "$profile" .sh)
                echo "  - $name"
            fi
        done
    else
        echo "  (no machines/ directory found in ${USER_DOTFILES})"
    fi
}

validate_user_dotfiles() {
    if [[ ! -d "$USER_DOTFILES" ]]; then
        echo "Error: User dotfiles directory not found: $USER_DOTFILES" >&2
        echo "Use --dotfiles to specify a different location" >&2
        exit 1
    fi

    if [[ ! -d "${USER_DOTFILES}/machines" ]]; then
        echo "Error: No machines/ directory found in: $USER_DOTFILES" >&2
        exit 1
    fi

    if [[ ! -d "${USER_DOTFILES}/tools" ]]; then
        echo "Error: No tools/ directory found in: $USER_DOTFILES" >&2
        exit 1
    fi
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    local machine=""
    local single_tool=""
    local dry_run=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--list)
                list_profiles
                exit 0
                ;;
            -t|--tool)
                single_tool="$2"
                shift 2
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -d|--dotfiles)
                USER_DOTFILES="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
            *)
                if [[ -z "$machine" ]]; then
                    machine="$1"
                else
                    echo "Too many arguments" >&2
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate machine argument
    if [[ -z "$machine" ]]; then
        echo "Error: Machine profile required" >&2
        echo ""
        usage
        exit 1
    fi

    # Validate user dotfiles structure
    validate_user_dotfiles

    local machine_profile="${USER_DOTFILES}/machines/${machine}.sh"
    if [[ ! -f "$machine_profile" ]]; then
        echo "Error: Machine profile not found: $machine_profile" >&2
        echo ""
        list_profiles
        exit 1
    fi

    echo "========================================"
    echo "==> Setting up: $machine"
    echo "========================================"
    echo ""
    echo "Framework directory: $FRAMEWORK_DIR"
    echo "User dotfiles: $USER_DOTFILES"
    echo "Machine profile: $machine_profile"

    # Source library files from framework
    source "${FRAMEWORK_DIR}/lib/repos.sh"
    source "${FRAMEWORK_DIR}/lib/layers.sh"
    source "${FRAMEWORK_DIR}/lib/builtins.sh"
    source "${FRAMEWORK_DIR}/lib/hooks.sh"

    # Load repos configuration from user dotfiles
    echo ""
    echo "==> Loading repository configuration..."
    local repos_conf="${USER_DOTFILES}/repos.conf"
    if [[ -f "$repos_conf" ]]; then
        load_repos_conf "$USER_DOTFILES"
    else
        echo "[WARN] No repos.conf found, external repos will not be available"
    fi

    # Source machine profile to get TOOLS array and layer assignments
    echo "==> Loading machine profile..."
    source "$machine_profile"

    # Validate TOOLS array exists
    if [[ -z "${TOOLS[*]:-}" ]]; then
        echo "Error: Machine profile does not define TOOLS array" >&2
        exit 1
    fi

    # Ensure external repositories exist (only those needed by current profile)
    echo ""
    echo "==> Ensuring external repositories..."
    for tool in "${TOOLS[@]}"; do
        local layers
        layers=$(get_tool_layers "$tool")
        ensure_repos_for_layers "$layers" "$USER_DOTFILES" "$tool" || true
    done

    # Process each tool
    local failed_tools=()
    local processed=0

    for tool in "${TOOLS[@]}"; do
        # If --tool specified, skip others
        if [[ -n "$single_tool" && "$tool" != "$single_tool" ]]; then
            continue
        fi

        if $dry_run; then
            echo ""
            echo "==> [DRY-RUN] Would process: $tool"
            local layers
            layers=$(get_tool_layers "$tool")
            echo "[INFO] Layers: $layers"
            continue
        fi

        if process_tool "$tool" "$USER_DOTFILES" "$machine"; then
            ((++processed))
        else
            failed_tools+=("$tool")
        fi
    done

    # Summary
    echo ""
    echo "========================================"
    echo "==> Setup complete!"
    echo "========================================"
    echo ""
    echo "Processed: $processed tool(s)"

    if [[ ${#failed_tools[@]} -gt 0 ]]; then
        echo ""
        echo "Failed tools:"
        for tool in "${failed_tools[@]}"; do
            echo "  - $tool"
        done
        exit 1
    fi
}

# Run main function
main "$@"
