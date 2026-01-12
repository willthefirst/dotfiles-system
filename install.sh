#!/usr/bin/env bash
# install.sh
# Main entry point for the dotfiles layering system
#
# This is the FRAMEWORK entry point. It uses the modular orchestrator
# architecture to install configurations from an external dotfiles repo.
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
# Install Functions
# ============================================================================

run_install() {
    local machine="$1"
    local single_tool="$2"
    local dry_run="$3"

    # Source the orchestrator (which sources all dependencies)
    source "${FRAMEWORK_DIR}/lib/orchestrator.sh"

    # Source resolver/repos for external repository management
    source "${FRAMEWORK_DIR}/lib/resolver/repos.sh"

    # Run pre-flight checks (skip in dry-run mode)
    if [[ "$dry_run" != "true" ]]; then
        if [[ -f "${USER_DOTFILES}/lib/helpers/preflight.sh" ]]; then
            source "${USER_DOTFILES}/lib/helpers/preflight.sh"
            if ! run_preflight_checks; then
                log_error "Pre-flight checks failed. Fix issues above and retry."
                exit 1
            fi
        fi
    fi

    # Initialize repos from repos.conf (uses new repos module)
    repos_init "$USER_DOTFILES"

    # Ensure external repos are cloned before processing
    # This needs to happen before orchestrator runs because layer resolution
    # depends on repos being present
    _ensure_external_repos_for_profile "${USER_DOTFILES}/machines/${machine}.sh"

    # Initialize the orchestrator
    local dry_run_flag=0
    [[ "$dry_run" == "true" ]] && dry_run_flag=1

    declare -A orch_config=(
        [dotfiles_dir]="$USER_DOTFILES"
        [dry_run]="$dry_run_flag"
        [verbose]="0"
    )

    if ! orchestrator_init orch_config; then
        log_error "Failed to initialize orchestrator"
        exit 1
    fi

    # Run the orchestrator
    declare -A result

    if [[ -n "$single_tool" ]]; then
        # Single tool mode
        log_section "Installing tool: $single_tool"
        orchestrator_run_tool "$single_tool" result || true
    else
        # Full profile mode
        orchestrator_run "${USER_DOTFILES}/machines/${machine}.sh" result || true
    fi

    # Exit with appropriate code
    if [[ "${result[success]:-0}" == "1" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Ensure external repos are cloned for all tools in a profile
# This is needed before orchestrator runs since layer resolution needs repos present
_ensure_external_repos_for_profile() {
    local profile_path="$1"

    if [[ ! -f "$profile_path" ]]; then
        return 0
    fi

    # Read the profile to extract TOOLS and their layers
    local content
    content=$(cat "$profile_path")

    # Parse TOOLS array (simple extraction)
    local tools_line
    tools_line=$(echo "$content" | grep -E '^\s*TOOLS=' | head -1 || true)

    if [[ -z "$tools_line" ]]; then
        return 0
    fi

    # Extract tool names (simplified parsing)
    local tools_str
    tools_str=$(echo "$content" | sed -n '/^TOOLS=(/,/)/p' | tr '\n' ' ' | sed 's/.*(\(.*\)).*/\1/' | tr -d '()' | xargs)

    # For each tool, check if it uses external repos and ensure they exist
    for tool in $tools_str; do
        local tool_conf="${USER_DOTFILES}/tools/${tool}/tool.conf"
        if [[ ! -f "$tool_conf" ]]; then
            continue
        fi

        # Get layer names for this tool from profile
        local layers_line
        layers_line=$(echo "$content" | grep -E "^${tool}_layers=" | head -1 || true)

        if [[ -z "$layers_line" ]]; then
            continue
        fi

        # Extract layer names
        local layers
        layers=$(echo "$layers_line" | sed 's/.*=(\(.*\))/\1/' | tr -d '()' | xargs)

        # Read tool.conf to find layer definitions
        local tool_content
        tool_content=$(cat "$tool_conf")

        # For each layer, check if it references an external repo
        for layer in $layers; do
            local layer_def
            layer_def=$(echo "$tool_content" | grep -E "^layers_${layer}=" | head -1 || true)

            if [[ -z "$layer_def" ]]; then
                continue
            fi

            # Extract the repo:path format (e.g., "STRIPE_DOTFILES:configs/git")
            local layer_spec
            layer_spec=$(echo "$layer_def" | sed 's/.*="\([^"]*\)"/\1/' | sed "s/.*='\([^']*\)'/\1/" | sed 's/.*=\([^ ]*\)/\1/')

            # Get the repo name (part before the colon)
            local repo_name="${layer_spec%%:*}"

            # Skip local layers
            if [[ "$repo_name" == "local" ]]; then
                continue
            fi

            # Ensure the external repo is cloned using new repos module
            if repos_is_configured "$repo_name"; then
                repos_ensure "$repo_name" || true
            fi
        done
    done
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

    # Set up logging bridge - user dotfiles can provide custom logging
    export DOTFILES_LOG_SOURCE="${USER_DOTFILES}/lib/helpers/log.sh"

    # Source logging first (before other libraries)
    source "${FRAMEWORK_DIR}/lib/log.sh"

    log_section "Setting up: $machine"
    log_detail "Framework: $FRAMEWORK_DIR"
    log_detail "Dotfiles: $USER_DOTFILES"
    log_detail "Profile: $machine_profile"

    run_install "$machine" "$single_tool" "$dry_run"
}

# Run main function
main "$@"
