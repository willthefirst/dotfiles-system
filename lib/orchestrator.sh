#!/usr/bin/env bash
# MODULE: orchestrator
# PURPOSE: Coordinate the full installation workflow
#
# PUBLIC API:
#   orchestrator_init(config_ref)          - Initialize with configuration
#   orchestrator_run(profile, result_ref)  - Run full installation for a profile
#   orchestrator_run_tool(tool_name, result_ref) - Run single tool installation
#   orchestrator_get_dotfiles_dir()        - Get configured dotfiles directory
#   orchestrator_is_dry_run()              - Check if dry-run mode is enabled
#
# CONFIGURATION (via config_ref associative array):
#   [dotfiles_dir]  - Path to dotfiles directory (required)
#   [dry_run]       - "1" for dry-run mode, "0" for real (default: 0)
#   [verbose]       - "1" for verbose logging (default: 0)
#
# RESULT (via result_ref associative array):
#   [tools_processed]   - Number of tools processed
#   [tools_succeeded]   - Number of tools that succeeded
#   [tools_failed]      - Number of tools that failed
#   [tools_skipped]     - Number of tools skipped
#   [failed_tools]      - Space-separated list of failed tool names
#   [success]           - "1" if all tools succeeded, "0" otherwise
#
# DEPENDENCIES:
#   core/fs.sh, core/log.sh, core/backup.sh, core/errors.sh
#   config/parser.sh, config/validator.sh, config/machine.sh
#   resolver/layers.sh
#   executor/runner.sh
#   contracts/tool_config.sh, contracts/machine_config.sh, contracts/hook_result.sh

[[ -n "${_ORCHESTRATOR_LOADED:-}" ]] && return 0
_ORCHESTRATOR_LOADED=1

# Source dependencies
_ORCHESTRATOR_DIR="${BASH_SOURCE[0]%/*}"
source "$_ORCHESTRATOR_DIR/core/fs.sh"
source "$_ORCHESTRATOR_DIR/core/log.sh"
source "$_ORCHESTRATOR_DIR/core/backup.sh"
source "$_ORCHESTRATOR_DIR/core/errors.sh"
source "$_ORCHESTRATOR_DIR/config/parser.sh"
source "$_ORCHESTRATOR_DIR/config/validator.sh"
source "$_ORCHESTRATOR_DIR/config/machine.sh"
source "$_ORCHESTRATOR_DIR/resolver/layers.sh"
source "$_ORCHESTRATOR_DIR/executor/runner.sh"
source "$_ORCHESTRATOR_DIR/contracts/tool_config.sh"
source "$_ORCHESTRATOR_DIR/contracts/machine_config.sh"
source "$_ORCHESTRATOR_DIR/contracts/hook_result.sh"

# --- State ---
_orchestrator_dotfiles_dir=""
_orchestrator_dry_run=0
_orchestrator_verbose=0
_orchestrator_initialized=0

# --- Initialization ---

# Initialize orchestrator with configuration
# Usage:
#   declare -A config=([dotfiles_dir]="/path" [dry_run]="0")
#   orchestrator_init config
# Returns: E_OK, E_INVALID_INPUT
orchestrator_init() {
    local -n __oi_config=$1

    # Validate required configuration
    if [[ -z "${__oi_config[dotfiles_dir]:-}" ]]; then
        log_error "orchestrator_init: dotfiles_dir is required"
        return $E_INVALID_INPUT
    fi

    _orchestrator_dotfiles_dir="${__oi_config[dotfiles_dir]}"
    _orchestrator_dry_run="${__oi_config[dry_run]:-0}"
    _orchestrator_verbose="${__oi_config[verbose]:-0}"

    # Expand tilde in dotfiles_dir
    if [[ "$_orchestrator_dotfiles_dir" == "~"* ]]; then
        _orchestrator_dotfiles_dir="${_orchestrator_dotfiles_dir/#\~/$HOME}"
    fi

    # Initialize sub-modules
    layer_resolver_init "$_orchestrator_dotfiles_dir" || return $?
    runner_init "$_orchestrator_dotfiles_dir" || return $?

    # Initialize backup directory
    local backup_dir="${_orchestrator_dotfiles_dir}/.backup"
    declare -A backup_cfg=([dir]="$backup_dir")
    backup_init backup_cfg

    _orchestrator_initialized=1
    return $E_OK
}

# Get configured dotfiles directory
orchestrator_get_dotfiles_dir() {
    printf '%s' "$_orchestrator_dotfiles_dir"
}

# Check if dry-run mode is enabled
# Returns: 0 if dry-run, 1 if real
orchestrator_is_dry_run() {
    [[ "$_orchestrator_dry_run" == "1" ]]
}

# --- Main Entry Points ---

# Run full installation for a machine profile
# Usage: orchestrator_run "/path/to/machines/profile.sh" result
# Returns: E_OK if all tools succeeded, E_GENERIC if any failed
orchestrator_run() {
    local profile_path="$1"
    local -n __or_result=$2

    if [[ "$_orchestrator_initialized" != "1" ]]; then
        log_error "orchestrator not initialized, call orchestrator_init first"
        return $E_INVALID_INPUT
    fi

    # Initialize result
    __or_result=(
        [tools_processed]=0
        [tools_succeeded]=0
        [tools_failed]=0
        [tools_skipped]=0
        [failed_tools]=""
        [success]="0"
    )

    # Resolve profile path if relative
    if [[ "$profile_path" != /* ]]; then
        profile_path="${_orchestrator_dotfiles_dir}/machines/${profile_path}"
    fi

    # Add .sh extension if missing
    if [[ "$profile_path" != *.sh ]]; then
        profile_path="${profile_path}.sh"
    fi

    log_section "Loading machine profile: $(basename "$profile_path" .sh)"

    # Load machine profile
    declare -A machine_config
    local rc=0
    config_load_machine_profile "$profile_path" machine_config || rc=$?

    if [[ $rc -ne 0 ]]; then
        log_error "Failed to load machine profile: $profile_path"
        return $rc
    fi

    # Get profile info
    local profile_name
    profile_name=$(machine_config_get_profile_name machine_config)
    local tool_count
    tool_count=$(machine_config_get_tool_count machine_config)

    log_step "Profile: $profile_name ($tool_count tools)"

    if orchestrator_is_dry_run; then
        log_warn "DRY-RUN MODE: No changes will be made"
    fi

    # Process each tool
    local i tool_name
    for ((i = 0; i < tool_count; i++)); do
        tool_name=$(machine_config_get_tool machine_config "$i")

        # Get layers for this tool from the machine config
        local layers
        layers=$(machine_config_get_tool_layers machine_config "$tool_name")

        declare -A tool_result
        _orchestrator_process_tool "$tool_name" "$layers" tool_result

        # Update aggregate result
        ((__or_result[tools_processed]++)) || true

        if [[ "${tool_result[success]}" == "1" ]]; then
            ((__or_result[tools_succeeded]++)) || true
        elif [[ "${tool_result[skipped]:-0}" == "1" ]]; then
            ((__or_result[tools_skipped]++)) || true
        else
            ((__or_result[tools_failed]++)) || true
            if [[ -n "${__or_result[failed_tools]}" ]]; then
                __or_result[failed_tools]+=" "
            fi
            __or_result[failed_tools]+="$tool_name"
        fi
    done

    # Set overall success
    if [[ "${__or_result[tools_failed]}" == "0" ]]; then
        __or_result[success]="1"
    fi

    # Log summary
    _orchestrator_log_summary __or_result

    if [[ "${__or_result[success]}" == "1" ]]; then
        return $E_OK
    else
        return $E_GENERIC
    fi
}

# Run installation for a single tool
# Usage: orchestrator_run_tool "git" result
# Returns: E_OK on success, error code on failure
orchestrator_run_tool() {
    local tool_name="$1"
    local -n __ort_result=$2

    if [[ "$_orchestrator_initialized" != "1" ]]; then
        log_error "orchestrator not initialized, call orchestrator_init first"
        return $E_INVALID_INPUT
    fi

    # Initialize result
    __ort_result=(
        [tools_processed]=1
        [tools_succeeded]=0
        [tools_failed]=0
        [tools_skipped]=0
        [failed_tools]=""
        [success]="0"
    )

    log_section "Installing tool: $tool_name"

    if orchestrator_is_dry_run; then
        log_warn "DRY-RUN MODE: No changes will be made"
    fi

    # Process the tool (without specific layers - will use default from tool.conf)
    declare -A tool_result
    _orchestrator_process_tool "$tool_name" "" tool_result

    if [[ "${tool_result[success]}" == "1" ]]; then
        __ort_result[tools_succeeded]=1
        __ort_result[success]="1"
        return $E_OK
    elif [[ "${tool_result[skipped]:-0}" == "1" ]]; then
        __ort_result[tools_skipped]=1
        return $E_OK
    else
        __ort_result[tools_failed]=1
        __ort_result[failed_tools]="$tool_name"
        return $E_GENERIC
    fi
}

# --- Internal Functions ---

# Process a single tool through the full pipeline
# Usage: _orchestrator_process_tool "git" "base work" result
# Modifies: result[success], result[error], result[skipped]
_orchestrator_process_tool() {
    local tool_name="$1"
    local layers_str="$2"
    local -n __opt_result=$3

    __opt_result=(
        [success]="0"
        [error]=""
        [skipped]="0"
    )

    local tool_dir="${_orchestrator_dotfiles_dir}/tools/${tool_name}"

    log_step "Processing: $tool_name"

    # Step 1: Parse tool config (JSON preferred, falls back to conf)
    declare -A raw_config
    local rc=0
    config_parse_tool "$tool_dir" raw_config || rc=$?

    if [[ $rc -eq $E_NOT_FOUND ]]; then
        log_skip "No tool.json or tool.conf found for $tool_name"
        __opt_result[skipped]="1"
        return $E_OK
    elif [[ $rc -ne 0 ]]; then
        log_error "Failed to parse tool config for $tool_name"
        __opt_result[error]="parse_failed"
        return $rc
    fi

    # Step 2: Build and validate ToolConfig
    declare -A tool_config
    if ! config_build_tool_config raw_config tool_config "$tool_dir"; then
        log_error "Invalid configuration for $tool_name"
        __opt_result[error]="validation_failed"
        return $E_VALIDATION
    fi

    # Step 3: Filter layers if machine profile specified specific ones
    if [[ -n "$layers_str" ]]; then
        _orchestrator_filter_layers tool_config "$layers_str"
    fi

    # Step 4: Resolve layer paths
    if ! layer_resolve_tool_config tool_config; then
        log_error "Failed to resolve layers for $tool_name"
        __opt_result[error]="resolution_failed"
        return $E_NOT_FOUND
    fi

    # Step 5: Validate resolved layers exist
    if ! layer_validate_resolved tool_config 2>/dev/null; then
        log_warn "Some layers missing for $tool_name, continuing anyway"
        # Don't fail, some layers may be optional
    fi

    # Step 6: Execute merge hook (or simulate in dry-run)
    if orchestrator_is_dry_run; then
        _orchestrator_dry_run_tool tool_config
        __opt_result[success]="1"
        return $E_OK
    fi

    declare -A hook_result
    if ! runner_run_merge tool_config hook_result; then
        local error_msg
        error_msg=$(hook_result_get_message hook_result 2>/dev/null || echo "unknown error")
        log_error "Merge hook failed for $tool_name: $error_msg"
        __opt_result[error]="merge_failed: $error_msg"
        return $E_GENERIC
    fi

    # Step 7: Execute install hook if present
    local install_hook
    install_hook=$(tool_config_get_install_hook tool_config)
    if [[ -n "$install_hook" ]]; then
        declare -A install_result
        if ! runner_run_install tool_config install_result; then
            local error_msg
            error_msg=$(hook_result_get_message install_result 2>/dev/null || echo "unknown error")
            log_warn "Install hook failed for $tool_name: $error_msg"
            # Don't fail the whole tool for install hook failure
        fi
    fi

    log_ok "$tool_name"
    __opt_result[success]="1"
    return $E_OK
}

# Filter tool config layers to only include specified ones
# Usage: _orchestrator_filter_layers tool_config "base work"
_orchestrator_filter_layers() {
    local -n __ofl_config=$1
    local layers_str="$2"

    # Get current layer count
    local current_count
    current_count=$(tool_config_get_layer_count __ofl_config)

    if [[ $current_count -eq 0 ]]; then
        return
    fi

    # Build set of requested layers
    declare -A requested_layers
    local layer
    for layer in $layers_str; do
        requested_layers["$layer"]=1
    done

    # Build new layer list with only requested layers
    declare -A new_config
    new_config=(
        [tool_name]="${__ofl_config[tool_name]}"
        [target]="${__ofl_config[target]}"
        [merge_hook]="${__ofl_config[merge_hook]}"
        [install_hook]="${__ofl_config[install_hook]:-}"
        [layer_count]=0
    )

    local i new_idx=0
    for ((i = 0; i < current_count; i++)); do
        local name
        name=$(tool_config_get_layer_name __ofl_config "$i")

        if [[ -n "${requested_layers[$name]+set}" ]]; then
            local source path
            source=$(tool_config_get_layer_source __ofl_config "$i")
            path=$(tool_config_get_layer_path __ofl_config "$i")

            new_config["layer_${new_idx}_name"]="$name"
            new_config["layer_${new_idx}_source"]="$source"
            new_config["layer_${new_idx}_path"]="$path"
            new_config["layer_${new_idx}_resolved"]=""
            ((new_idx++)) || true
        fi
    done

    new_config[layer_count]=$new_idx

    # Copy back to original config
    for key in "${!new_config[@]}"; do
        __ofl_config["$key"]="${new_config[$key]}"
    done

    # Clear any old layer entries
    for ((i = new_idx; i < current_count; i++)); do
        unset "__ofl_config[layer_${i}_name]"
        unset "__ofl_config[layer_${i}_source]"
        unset "__ofl_config[layer_${i}_path]"
        unset "__ofl_config[layer_${i}_resolved]"
    done
}

# Simulate tool processing in dry-run mode
# Usage: _orchestrator_dry_run_tool tool_config
_orchestrator_dry_run_tool() {
    local -n __odrt_config=$1

    local tool_name
    tool_name=$(tool_config_get_tool_name __odrt_config)
    local target
    target=$(tool_config_get_target __odrt_config)
    local merge_hook
    merge_hook=$(tool_config_get_merge_hook __odrt_config)
    local layer_count
    layer_count=$(tool_config_get_layer_count __odrt_config)

    log_detail "  Tool: $tool_name"
    log_detail "  Target: $target"
    log_detail "  Merge hook: $merge_hook"
    log_detail "  Layers ($layer_count):"

    local i
    for ((i = 0; i < layer_count; i++)); do
        local name resolved
        name=$(tool_config_get_layer_name __odrt_config "$i")
        resolved=$(tool_config_get_layer_resolved __odrt_config "$i")
        log_detail "    - $name: $resolved"
    done

    log_ok "[DRY-RUN] $tool_name"
}

# Log a summary of the orchestration results
# Usage: _orchestrator_log_summary result
_orchestrator_log_summary() {
    local -n __ols_result=$1

    echo ""
    log_section "Summary"
    log_step "Processed: ${__ols_result[tools_processed]} tools"
    log_ok "Succeeded: ${__ols_result[tools_succeeded]}"

    if [[ "${__ols_result[tools_skipped]}" -gt 0 ]]; then
        log_skip "Skipped: ${__ols_result[tools_skipped]}"
    fi

    if [[ "${__ols_result[tools_failed]}" -gt 0 ]]; then
        log_error "Failed: ${__ols_result[tools_failed]} (${__ols_result[failed_tools]})"
    fi
}

# --- Testing Support ---

# Reset orchestrator state (for testing)
orchestrator_reset() {
    _orchestrator_dotfiles_dir=""
    _orchestrator_dry_run=0
    _orchestrator_verbose=0
    _orchestrator_initialized=0
}
