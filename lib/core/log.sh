#!/usr/bin/env bash
# MODULE: core/log
# PURPOSE: Logging with configurable output and mock support
#
# PUBLIC API:
#   log_init(config_ref)     - Initialize logger (config: output, level, color)
#   log_section(msg)         - Major section header
#   log_step(msg)            - Step within section
#   log_detail(msg)          - Detail message (verbose only)
#   log_ok(msg)              - Success message
#   log_warn(msg)            - Warning message
#   log_error(msg)           - Error message
#   log_skip(msg)            - Skipped operation
#
# MOCK API (for testing):
#   log_mock_reset()         - Clear captured logs
#   log_mock_get()           - Get all captured logs
#   log_mock_assert(pattern) - Assert log contains pattern (returns 0/1)
#   log_mock_count()         - Get count of captured log entries
#
# CONFIGURATION:
#   config[output]  - "mock" for testing, or file path (default: /dev/stderr)
#   config[level]   - "debug", "info", "warn", "error" (default: info)
#   config[color]   - 1 for color, 0 for plain (default: 1)
#
# DEPENDENCIES: None (leaf module)

[[ -n "${_CORE_LOG_LOADED:-}" ]] && return 0
_CORE_LOG_LOADED=1

# --- State ---
_log_output="/dev/stderr"  # or "mock" for testing
_log_level="info"          # debug, info, warn, error
_log_color=1
declare -ga _log_mock_buffer=()

# Log level priorities for filtering
declare -gA _LOG_LEVELS=(
    [debug]=0
    [info]=1
    [warn]=2
    [error]=3
)

# --- Initialization ---

# Initialize the logger with configuration
# Usage: declare -A cfg=([output]="mock" [level]="debug"); log_init cfg
log_init() {
    local config_ref="${1:-}"

    if [[ -n "$config_ref" ]]; then
        local -n config="$config_ref" 2>/dev/null || true
        _log_output="${config[output]:-/dev/stderr}"
        _log_level="${config[level]:-info}"
        _log_color="${config[color]:-1}"
    fi

    if [[ "$_log_output" == "mock" ]]; then
        _log_mock_buffer=()
    fi
}

# --- Internal ---

# Check if a message at given level should be logged
_log_should_log() {
    local msg_level="$1"
    local current_priority="${_LOG_LEVELS[$_log_level]:-1}"
    local msg_priority="${_LOG_LEVELS[$msg_level]:-1}"
    [[ $msg_priority -ge $current_priority ]]
}

# Write a log message
_log_write() {
    local level="$1"
    local msg="$2"
    local prefix="$3"
    local color="$4"

    # Check level filter
    if ! _log_should_log "$level"; then
        return 0
    fi

    if [[ "$_log_output" == "mock" ]]; then
        _log_mock_buffer+=("[$level] $msg")
        return 0
    fi

    if [[ "$_log_color" == 1 && -t 2 ]]; then
        printf '%b%s%b %s\n' "$color" "$prefix" '\033[0m' "$msg" >> "$_log_output"
    else
        printf '%s %s\n' "$prefix" "$msg" >> "$_log_output"
    fi
}

# --- Public API ---

# Major section header (always logged unless error-only)
log_section() {
    _log_write "info" "$1" "==>" '\033[1;34m'
}

# Step within section
log_step() {
    _log_write "info" "$1" "  ->" '\033[0;36m'
}

# Detail message (only in debug mode)
log_detail() {
    _log_write "debug" "$1" "     " '\033[0;37m'
}

# Success message
log_ok() {
    _log_write "info" "$1" "  ✓" '\033[0;32m'
}

# Warning message
log_warn() {
    _log_write "warn" "$1" "  ⚠" '\033[0;33m'
}

# Error message (always logged)
log_error() {
    _log_write "error" "$1" "  ✗" '\033[0;31m'
}

# Skipped operation
log_skip() {
    _log_write "info" "$1" "  ○" '\033[0;90m'
}

# --- Mock API ---

# Clear all captured logs
log_mock_reset() {
    _log_mock_buffer=()
}

# Get all captured logs (one per line)
log_mock_get() {
    printf '%s\n' "${_log_mock_buffer[@]}"
}

# Assert that logs contain a pattern
# Usage: log_mock_assert "error" && echo "found"
log_mock_assert() {
    local pattern="$1"
    printf '%s\n' "${_log_mock_buffer[@]}" | grep -q "$pattern"
}

# Get count of captured log entries
log_mock_count() {
    echo "${#_log_mock_buffer[@]}"
}
