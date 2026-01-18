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
    echo "Machine profiles are defined in <dotfiles>/machines/<name>.json"
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
        for profile in "${USER_DOTFILES}"/machines/*.json; do
            if [[ -f "$profile" ]]; then
                local name
                name=$(basename "$profile" .json)
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
    _ensure_external_repos_for_profile "${USER_DOTFILES}/machines/${machine}.json"

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
        # Single tool mode - pass profile path to respect layer settings
        log_section "Installing tool: $single_tool"
        orchestrator_run_tool "$single_tool" result "${USER_DOTFILES}/machines/${machine}.json" || true
    else
        # Full profile mode
        orchestrator_run "${USER_DOTFILES}/machines/${machine}.json" result || true
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

    # Read the machine profile JSON
    local profile_content
    profile_content=$(cat "$profile_path")

    # Validate JSON
    if ! echo "$profile_content" | jq . &>/dev/null; then
        return 0
    fi

    # Get all tool names from the profile
    local tools
    tools=$(echo "$profile_content" | jq -r '.tools | keys[]' 2>/dev/null) || return 0

    # For each tool, check if it uses external repos and ensure they exist
    for tool in $tools; do
        local tool_json="${USER_DOTFILES}/tools/${tool}/tool.json"
        if [[ ! -f "$tool_json" ]]; then
            continue
        fi

        # Read tool.json
        local tool_content
        tool_content=$(cat "$tool_json")

        # Get all layer sources from tool.json
        local i=0
        while true; do
            local source
            source=$(echo "$tool_content" | jq -r ".layers[$i].source // empty")
            [[ -z "$source" ]] && break

            # Skip local layers
            if [[ "$source" != "local" ]]; then
                # Ensure the external repo is cloned using repos module
                if repos_is_configured "$source"; then
                    repos_ensure "$source" || true
                fi
            fi
            ((i++)) || true
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

    local machine_profile="${USER_DOTFILES}/machines/${machine}.json"
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
