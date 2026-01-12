#!/usr/bin/env bash
# MODULE: core/backup
# PURPOSE: Backup creation and restoration using fs abstraction
#
# PUBLIC API:
#   backup_init(config_ref)        - Initialize (config: dir)
#   backup_create(path, result_ref) - Backup file/dir, stores backup path in result_ref
#   backup_restore(backup_path, original_path) - Restore from backup
#   backup_list()                  - List all backups (one per line)
#   backup_cleanup(days)           - Remove backups older than N days
#   backup_get_dir()               - Get current backup directory
#
# DEPENDENCIES: core/fs.sh, core/log.sh, core/errors.sh

[[ -n "${_CORE_BACKUP_LOADED:-}" ]] && return 0
_CORE_BACKUP_LOADED=1

# Source dependencies
_BACKUP_SCRIPT_DIR="${BASH_SOURCE[0]%/*}"
source "$_BACKUP_SCRIPT_DIR/fs.sh"
source "$_BACKUP_SCRIPT_DIR/log.sh"
source "$_BACKUP_SCRIPT_DIR/errors.sh"

# --- State ---
_backup_dir="${DOTFILES_BACKUP_DIR:-$HOME/.dotfiles-backup}"

# --- Initialization ---

# Initialize backup module
# Usage: declare -A cfg=([dir]="/path/to/backups"); backup_init cfg
backup_init() {
    local config_ref="${1:-}"

    if [[ -n "$config_ref" ]]; then
        local -n config="$config_ref" 2>/dev/null || true
        _backup_dir="${config[dir]:-$_backup_dir}"
    fi

    fs_mkdir "$_backup_dir"
}

# Get current backup directory
backup_get_dir() {
    echo "$_backup_dir"
}

# --- Public API ---

# Create a backup of a file or directory
# Usage: backup_create "/path/to/file" result_var
# Sets result_var to the backup path (empty if nothing to backup)
# Returns: E_OK on success, E_BACKUP on failure
backup_create() {
    local path="$1"
    local -n __backup_result="$2"
    __backup_result=""

    # Nothing to backup if path doesn't exist
    if ! fs_exists "$path"; then
        return $E_OK
    fi

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local basename
    basename=$(basename "$path")
    local backup_path="$_backup_dir/${basename}.${timestamp}"

    log_detail "Backing up $path to $backup_path"

    # Handle different types
    if fs_is_symlink "$path"; then
        # For symlinks, store the link target
        local link_target
        link_target=$(fs_readlink "$path")
        fs_write "$backup_path" "__SYMLINK:$link_target"
    elif fs_is_dir "$path"; then
        # For directories in mock mode, just mark as dir
        # For real mode, use cp -r
        if [[ "$(fs_get_backend)" == "real" ]]; then
            if ! cp -r "$path" "$backup_path" 2>/dev/null; then
                log_error "Failed to backup directory: $path"
                return $E_BACKUP
            fi
        else
            fs_mkdir "$backup_path"
            # Copy children in mock
            local prefix="$path/"
            for key in "${!_fs_mock_types[@]}"; do
                if [[ "$key" == "$prefix"* ]]; then
                    local rel="${key#$prefix}"
                    local child_backup="$backup_path/$rel"
                    if [[ "${_fs_mock_types[$key]}" == "file" ]]; then
                        local child_content
                        child_content=$(fs_read "$key")
                        fs_write "$child_backup" "$child_content"
                    fi
                fi
            done
        fi
    else
        # Regular file
        local content
        content=$(fs_read "$path") || {
            log_error "Failed to read file for backup: $path"
            return $E_BACKUP
        }
        fs_write "$backup_path" "$content"
    fi

    __backup_result="$backup_path"
    return $E_OK
}

# Restore from a backup
# Usage: backup_restore "/backups/file.20240115_123456" "/original/path"
backup_restore() {
    local backup_path="$1"
    local original_path="$2"

    if ! fs_exists "$backup_path"; then
        log_error "Backup not found: $backup_path"
        return $E_NOT_FOUND
    fi

    log_step "Restoring $original_path from $backup_path"

    # Check if it's a symlink backup
    local content
    content=$(fs_read "$backup_path") || return $E_BACKUP

    if [[ "$content" == "__SYMLINK:"* ]]; then
        local link_target="${content#__SYMLINK:}"
        fs_remove "$original_path"
        fs_symlink "$link_target" "$original_path"
    elif fs_is_dir "$backup_path"; then
        # Directory restore
        fs_remove_rf "$original_path"
        if [[ "$(fs_get_backend)" == "real" ]]; then
            cp -r "$backup_path" "$original_path"
        else
            fs_mkdir "$original_path"
            # Copy children in mock
            local prefix="$backup_path/"
            for key in "${!_fs_mock_types[@]}"; do
                if [[ "$key" == "$prefix"* ]]; then
                    local rel="${key#$prefix}"
                    local restored="$original_path/$rel"
                    if [[ "${_fs_mock_types[$key]}" == "file" ]]; then
                        local child_content
                        child_content=$(fs_read "$key")
                        fs_write "$restored" "$child_content"
                    fi
                fi
            done
        fi
    else
        # Regular file restore
        fs_remove "$original_path"
        fs_write "$original_path" "$content"
    fi

    log_ok "Restored $original_path"
    return $E_OK
}

# List all backups
backup_list() {
    if [[ "$(fs_get_backend)" == "real" ]]; then
        ls -1 "$_backup_dir" 2>/dev/null || true
    else
        fs_list "$_backup_dir"
    fi
}

# Remove backups older than N days
# Usage: backup_cleanup 30
backup_cleanup() {
    local days="${1:-30}"

    log_step "Cleaning up backups older than $days days"

    if [[ "$(fs_get_backend)" == "real" ]]; then
        find "$_backup_dir" -type f -mtime +"$days" -delete 2>/dev/null || true
        find "$_backup_dir" -type d -empty -delete 2>/dev/null || true
    else
        # In mock mode, we can't easily check timestamps
        # Just log that we would clean up
        log_detail "Mock mode: would clean up backups older than $days days"
    fi

    return $E_OK
}
