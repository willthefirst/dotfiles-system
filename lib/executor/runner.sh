#!/usr/bin/env bash
# MODULE: executor/runner
# PURPOSE: Hook execution with environment isolation
#
# PUBLIC API:
#   runner_init(dotfiles_dir)          - Initialize runner with dotfiles directory
#   runner_build_env(config_ref, env_ref)  - Build env vars from ToolConfig
#   runner_execute(hook_spec, config_ref, result_ref) - Execute a hook
#   runner_execute_builtin(name, config_ref, result_ref) - Execute a builtin
#   runner_execute_script(path, config_ref, result_ref) - Execute a custom script
#   runner_get_dotfiles_dir()          - Get configured dotfiles directory
#
# DEPENDENCIES:
#   core/fs.sh, core/log.sh, core/backup.sh, core/errors.sh
#   contracts/tool_config.sh, contracts/hook_result.sh
#   executor/registry.sh

[[ -n "${_EXECUTOR_RUNNER_LOADED:-}" ]] && return 0
_EXECUTOR_RUNNER_LOADED=1

# Source dependencies
_EXECUTOR_RUNNER_DIR="${BASH_SOURCE[0]%/*}"
source "$_EXECUTOR_RUNNER_DIR/../core/fs.sh"
source "$_EXECUTOR_RUNNER_DIR/../core/log.sh"
source "$_EXECUTOR_RUNNER_DIR/../core/backup.sh"
source "$_EXECUTOR_RUNNER_DIR/../core/errors.sh"
source "$_EXECUTOR_RUNNER_DIR/../contracts/tool_config.sh"
source "$_EXECUTOR_RUNNER_DIR/../contracts/hook_result.sh"
source "$_EXECUTOR_RUNNER_DIR/registry.sh"

# Source builtins
source "$_EXECUTOR_RUNNER_DIR/builtins/symlink.sh"
source "$_EXECUTOR_RUNNER_DIR/builtins/concat.sh"
source "$_EXECUTOR_RUNNER_DIR/builtins/source.sh"
source "$_EXECUTOR_RUNNER_DIR/builtins/json-merge.sh"
source "$_EXECUTOR_RUNNER_DIR/builtins/skip.sh"

# --- State ---
_runner_dotfiles_dir=""
_runner_machine=""

# --- Initialization ---

# Initialize runner with dotfiles directory
# Usage: runner_init "/path/to/dotfiles"
runner_init() {
    local dotfiles_dir="$1"

    if [[ -z "$dotfiles_dir" ]]; then
        return $E_INVALID_INPUT
    fi

    # Expand tilde if present
    if [[ "$dotfiles_dir" == "~"* ]]; then
        dotfiles_dir="${dotfiles_dir/#\~/$HOME}"
    fi

    _runner_dotfiles_dir="$dotfiles_dir"

    # Register default builtin strategies
    strategy_register "symlink" "builtin_merge_symlink"
    strategy_register "concat" "builtin_merge_concat"
    strategy_register "source" "builtin_merge_source"
    strategy_register "json-merge" "builtin_merge_json"
    strategy_register "json" "builtin_merge_json"
    strategy_register "skip" "builtin_skip"

    return $E_OK
}

# Get configured dotfiles directory
runner_get_dotfiles_dir() {
    printf '%s' "$_runner_dotfiles_dir"
}

# Set machine/profile name for environment
runner_set_machine() {
    _runner_machine="$1"
}

# Get configured machine name
runner_get_machine() {
    printf '%s' "$_runner_machine"
}

# --- Environment Building ---

# Detect the current operating system
_runner_detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux) echo "linux" ;;
        *) echo "unknown" ;;
    esac
}

# Build environment variables from a ToolConfig
# Usage: runner_build_env config env_vars
# env_vars will contain: TOOL, TARGET, LAYERS, LAYER_PATHS, DOTFILES_DIR, OS, MACHINE
runner_build_env() {
    local -n __rb_config=$1
    local -n __rb_env=$2

    local tool_name
    tool_name=$(tool_config_get_tool_name __rb_config)

    local target
    target=$(tool_config_get_target __rb_config)
    # Expand tilde in target
    if [[ "$target" == "~"* ]]; then
        target="${target/#\~/$HOME}"
    fi

    # Build layer names and paths
    local layer_count
    layer_count=$(tool_config_get_layer_count __rb_config)

    local layers=""
    local layer_paths=""

    local i
    for ((i = 0; i < layer_count; i++)); do
        local name
        name=$(tool_config_get_layer_name __rb_config "$i")
        local resolved
        resolved=$(tool_config_get_layer_resolved __rb_config "$i")

        if [[ -n "$layers" ]]; then
            layers+=":"
            layer_paths+=":"
        fi
        layers+="$name"
        layer_paths+="$resolved"
    done

    __rb_env=(
        [TOOL]="$tool_name"
        [TARGET]="$target"
        [LAYERS]="$layers"
        [LAYER_PATHS]="$layer_paths"
        [DOTFILES_DIR]="$_runner_dotfiles_dir"
        [OS]="$(_runner_detect_os)"
        [MACHINE]="$_runner_machine"
    )

    return $E_OK
}

# --- Hook Execution ---

# Execute a hook (builtin or custom script)
# Usage: runner_execute "builtin:symlink" config result
#        runner_execute "./merge.sh" config result
runner_execute() {
    local hook_spec="$1"
    local -n __re_config=$2
    local -n __re_result=$3

    if [[ -z "$hook_spec" ]]; then
        hook_result_new_failure __re_result $E_INVALID_INPUT "hook_spec is required"
        return $E_INVALID_INPUT
    fi

    if [[ "$hook_spec" == "builtin:"* ]]; then
        # Extract builtin name
        local builtin_name="${hook_spec#builtin:}"
        runner_execute_builtin "$builtin_name" __re_config __re_result
        return $?
    else
        # Custom script
        runner_execute_script "$hook_spec" __re_config __re_result
        return $?
    fi
}

# Execute a builtin strategy
# Usage: runner_execute_builtin "symlink" config result
runner_execute_builtin() {
    local name="$1"
    local -n __reb_config=$2
    local -n __reb_result=$3

    if ! strategy_exists "$name"; then
        hook_result_new_failure __reb_result $E_NOT_FOUND "Unknown builtin strategy: $name"
        return $E_NOT_FOUND
    fi

    local handler
    handler=$(strategy_get "$name")

    log_step "Executing builtin:$name"

    # Call the handler function with config and result
    # Handler is responsible for populating result
    local rc=0
    "$handler" __reb_config __reb_result || rc=$?

    if [[ $rc -ne 0 ]]; then
        # If handler didn't set an error, set a generic one
        if hook_result_is_success __reb_result 2>/dev/null; then
            hook_result_new_failure __reb_result "$rc" "Builtin $name failed with code $rc"
        fi
        return $rc
    fi

    return $E_OK
}

# Execute a custom script hook
# Usage: runner_execute_script "./merge.sh" config result
runner_execute_script() {
    local script_path="$1"
    local -n __res_config=$2
    local -n __res_result=$3

    # Resolve relative paths against dotfiles_dir/tools/<tool>
    if [[ "$script_path" != /* ]]; then
        local tool_name
        tool_name=$(tool_config_get_tool_name __res_config)
        script_path="$_runner_dotfiles_dir/tools/$tool_name/$script_path"
    fi

    # Check script exists
    if ! fs_exists "$script_path"; then
        hook_result_new_failure __res_result $E_NOT_FOUND "Hook script not found: $script_path"
        return $E_NOT_FOUND
    fi

    log_step "Executing script: $script_path"

    # Build environment
    declare -A env_vars
    runner_build_env __res_config env_vars

    # Execute script with environment
    # For real filesystem, run in subprocess with exported env
    # For mock, we need to handle differently
    if [[ "$(fs_get_backend)" == "real" ]]; then
        local rc=0
        (
            export TOOL="${env_vars[TOOL]}"
            export TARGET="${env_vars[TARGET]}"
            export LAYERS="${env_vars[LAYERS]}"
            export LAYER_PATHS="${env_vars[LAYER_PATHS]}"
            export DOTFILES_DIR="${env_vars[DOTFILES_DIR]}"
            export OS="${env_vars[OS]}"
            export MACHINE="${env_vars[MACHINE]}"

            # Make script executable if needed
            [[ -x "$script_path" ]] || chmod +x "$script_path"

            # Execute script using current bash interpreter to preserve bash 4+ features
            # This prevents scripts with #!/usr/bin/env bash from falling back to system bash 3.2
            "$BASH" "$script_path"
        ) || rc=$?

        if [[ $rc -ne 0 ]]; then
            hook_result_new_failure __res_result "$rc" "Script failed with exit code $rc"
            return $rc
        fi

        hook_result_new __res_result 1
        hook_result_add_file __res_result "${env_vars[TARGET]}"
    else
        # In mock mode, just record that we would execute the script
        log_detail "Mock mode: would execute $script_path"
        hook_result_new __res_result 1
        hook_result_add_file __res_result "${env_vars[TARGET]}"
    fi

    return $E_OK
}

# --- Convenience Functions ---

# Execute merge hook from a fully resolved ToolConfig
# This is the main entry point for the orchestrator
# Usage: runner_run_merge config result
runner_run_merge() {
    local -n __rrm_config=$1
    local -n __rrm_result=$2

    local merge_hook
    merge_hook=$(tool_config_get_merge_hook __rrm_config)

    if [[ -z "$merge_hook" ]]; then
        hook_result_new_failure __rrm_result $E_INVALID_INPUT "No merge hook defined"
        return $E_INVALID_INPUT
    fi

    runner_execute "$merge_hook" __rrm_config __rrm_result
    return $?
}

# Execute install hook from a fully resolved ToolConfig (if defined)
# Usage: runner_run_install config result
runner_run_install() {
    local -n __rri_config=$1
    local -n __rri_result=$2

    local install_hook
    install_hook=$(tool_config_get_install_hook __rri_config)

    if [[ -z "$install_hook" ]]; then
        # No install hook is valid - just return success
        hook_result_new __rri_result 1
        return $E_OK
    fi

    runner_execute "$install_hook" __rri_config __rri_result
    return $?
}
