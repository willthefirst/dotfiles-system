#!/usr/bin/env bash
# MODULE: core/fs
# PURPOSE: Filesystem operations with injectable backend
#
# PUBLIC API:
#   fs_init(backend)           - Initialize with "real" or "mock" backend
#   fs_read(path)              - Read file contents to stdout
#   fs_write(path, content)    - Write content to file
#   fs_append(path, content)   - Append content to file
#   fs_exists(path)            - Check if path exists (file or dir)
#   fs_is_file(path)           - Check if path is a regular file
#   fs_is_dir(path)            - Check if path is a directory
#   fs_is_symlink(path)        - Check if path is a symlink
#   fs_remove(path)            - Remove file or symlink
#   fs_remove_rf(path)         - Remove recursively (dirs)
#   fs_mkdir(path)             - Create directory (with parents)
#   fs_symlink(source, target) - Create symlink (source -> target)
#   fs_readlink(path)          - Read symlink target
#   fs_list(path)              - List directory contents
#   fs_copy(src, dst)          - Copy file
#   fs_get_backend()           - Get current backend name
#
# MOCK API (for testing):
#   fs_mock_reset()            - Clear all mock state
#   fs_mock_set(path, content) - Set mock file content
#   fs_mock_set_dir(path)      - Set mock directory
#   fs_mock_set_symlink(path, target) - Set mock symlink
#   fs_mock_get(path)          - Get mock file content
#   fs_mock_calls()            - Get list of operations performed
#   fs_mock_assert_written(path, content) - Assert file was written with content
#   fs_mock_assert_call(operation)  - Assert operation was called
#
# DEPENDENCIES: None (leaf module)

[[ -n "${_CORE_FS_LOADED:-}" ]] && return 0
_CORE_FS_LOADED=1

# --- State ---
_fs_backend="real"
declare -gA _fs_mock_files=()
declare -gA _fs_mock_types=()  # "file", "dir", "symlink"
declare -gA _fs_mock_symlinks=()  # symlink target paths
declare -ga _fs_mock_calls=()

# --- Initialization ---

# Initialize filesystem backend
# Usage: fs_init "mock"  # for tests
#        fs_init "real"  # for production (default)
fs_init() {
    _fs_backend="${1:-real}"
    if [[ "$_fs_backend" == "mock" ]]; then
        _fs_mock_files=()
        _fs_mock_types=()
        _fs_mock_symlinks=()
        _fs_mock_calls=()
    fi
}

# Get current backend
fs_get_backend() {
    echo "$_fs_backend"
}

# --- Public API ---

# Read file contents to stdout
fs_read() {
    local path="$1"
    _fs_mock_calls+=("read:$path")

    case "$_fs_backend" in
        real)
            cat "$path" 2>/dev/null
            ;;
        mock)
            if [[ -n "${_fs_mock_files[$path]+set}" ]]; then
                printf '%s' "${_fs_mock_files[$path]}"
            else
                return 1
            fi
            ;;
    esac
}

# Write content to file
fs_write() {
    local path="$1"
    local content="$2"
    _fs_mock_calls+=("write:$path")

    case "$_fs_backend" in
        real)
            local dir
            dir=$(dirname "$path")
            [[ -d "$dir" ]] || mkdir -p "$dir"
            printf '%s' "$content" > "$path"
            ;;
        mock)
            _fs_mock_files["$path"]="$content"
            _fs_mock_types["$path"]="file"
            ;;
    esac
}

# Append content to file
fs_append() {
    local path="$1"
    local content="$2"
    _fs_mock_calls+=("append:$path")

    case "$_fs_backend" in
        real)
            local dir
            dir=$(dirname "$path")
            [[ -d "$dir" ]] || mkdir -p "$dir"
            printf '%s' "$content" >> "$path"
            ;;
        mock)
            _fs_mock_files["$path"]+="$content"
            _fs_mock_types["$path"]="file"
            ;;
    esac
}

# Check if path exists (file, dir, or symlink)
fs_exists() {
    local path="$1"

    case "$_fs_backend" in
        real)
            [[ -e "$path" || -L "$path" ]]
            ;;
        mock)
            [[ -n "${_fs_mock_types[$path]+set}" ]]
            ;;
    esac
}

# Check if path is a regular file
fs_is_file() {
    local path="$1"

    case "$_fs_backend" in
        real)
            [[ -f "$path" ]]
            ;;
        mock)
            [[ "${_fs_mock_types[$path]:-}" == "file" ]]
            ;;
    esac
}

# Check if path is a directory
fs_is_dir() {
    local path="$1"

    case "$_fs_backend" in
        real)
            [[ -d "$path" ]]
            ;;
        mock)
            [[ "${_fs_mock_types[$path]:-}" == "dir" ]]
            ;;
    esac
}

# Check if path is a symlink
fs_is_symlink() {
    local path="$1"

    case "$_fs_backend" in
        real)
            [[ -L "$path" ]]
            ;;
        mock)
            [[ "${_fs_mock_types[$path]:-}" == "symlink" ]]
            ;;
    esac
}

# Remove file or symlink
fs_remove() {
    local path="$1"
    _fs_mock_calls+=("remove:$path")

    case "$_fs_backend" in
        real)
            rm -f "$path" 2>/dev/null || true
            ;;
        mock)
            unset "_fs_mock_files[$path]"
            unset "_fs_mock_types[$path]"
            unset "_fs_mock_symlinks[$path]"
            ;;
    esac
}

# Remove recursively (for directories)
fs_remove_rf() {
    local path="$1"
    _fs_mock_calls+=("remove_rf:$path")

    case "$_fs_backend" in
        real)
            rm -rf "$path" 2>/dev/null || true
            ;;
        mock)
            # Remove path and all children
            for key in "${!_fs_mock_types[@]}"; do
                if [[ "$key" == "$path" || "$key" == "$path/"* ]]; then
                    unset "_fs_mock_files[$key]"
                    unset "_fs_mock_types[$key]"
                    unset "_fs_mock_symlinks[$key]"
                fi
            done
            ;;
    esac
}

# Create directory (with parents)
fs_mkdir() {
    local path="$1"
    _fs_mock_calls+=("mkdir:$path")

    case "$_fs_backend" in
        real)
            mkdir -p "$path"
            ;;
        mock)
            _fs_mock_types["$path"]="dir"
            ;;
    esac
}

# Create symlink
# Usage: fs_symlink "/actual/file" "/path/to/link"
fs_symlink() {
    local source="$1"
    local target="$2"
    _fs_mock_calls+=("symlink:$source->$target")

    case "$_fs_backend" in
        real)
            ln -sf "$source" "$target"
            ;;
        mock)
            _fs_mock_types["$target"]="symlink"
            _fs_mock_symlinks["$target"]="$source"
            ;;
    esac
}

# Read symlink target
fs_readlink() {
    local path="$1"
    _fs_mock_calls+=("readlink:$path")

    case "$_fs_backend" in
        real)
            readlink "$path" 2>/dev/null
            ;;
        mock)
            if [[ "${_fs_mock_types[$path]:-}" == "symlink" ]]; then
                printf '%s' "${_fs_mock_symlinks[$path]}"
            else
                return 1
            fi
            ;;
    esac
}

# List directory contents (one per line)
fs_list() {
    local path="$1"
    _fs_mock_calls+=("list:$path")

    case "$_fs_backend" in
        real)
            ls -1 "$path" 2>/dev/null
            ;;
        mock)
            # List entries that are direct children of path
            local prefix="$path/"
            for key in "${!_fs_mock_types[@]}"; do
                if [[ "$key" == "$prefix"* ]]; then
                    local rel="${key#$prefix}"
                    # Only direct children (no slashes)
                    if [[ "$rel" != */* ]]; then
                        echo "$rel"
                    fi
                fi
            done
            ;;
    esac
}

# Copy file
fs_copy() {
    local src="$1"
    local dst="$2"
    _fs_mock_calls+=("copy:$src->$dst")

    case "$_fs_backend" in
        real)
            cp "$src" "$dst"
            ;;
        mock)
            if [[ -n "${_fs_mock_files[$src]+set}" ]]; then
                _fs_mock_files["$dst"]="${_fs_mock_files[$src]}"
                _fs_mock_types["$dst"]="${_fs_mock_types[$src]}"
            else
                return 1
            fi
            ;;
    esac
}

# --- Mock API ---

# Clear all mock state
fs_mock_reset() {
    _fs_mock_files=()
    _fs_mock_types=()
    _fs_mock_symlinks=()
    _fs_mock_calls=()
}

# Set mock file content
fs_mock_set() {
    local path="$1"
    local content="$2"
    _fs_mock_files["$path"]="$content"
    _fs_mock_types["$path"]="file"
}

# Set mock directory
fs_mock_set_dir() {
    local path="$1"
    _fs_mock_types["$path"]="dir"
}

# Set mock symlink
fs_mock_set_symlink() {
    local path="$1"
    local target="$2"
    _fs_mock_types["$path"]="symlink"
    _fs_mock_symlinks["$path"]="$target"
}

# Get mock file content
fs_mock_get() {
    local path="$1"
    printf '%s' "${_fs_mock_files[$path]:-}"
}

# Get list of operations performed (one per line)
fs_mock_calls() {
    printf '%s\n' "${_fs_mock_calls[@]}"
}

# Assert file was written with specific content
fs_mock_assert_written() {
    local path="$1"
    local expected="$2"
    [[ "${_fs_mock_files[$path]:-}" == "$expected" ]]
}

# Assert operation was called (pattern match)
fs_mock_assert_call() {
    local pattern="$1"
    printf '%s\n' "${_fs_mock_calls[@]}" | grep -q "$pattern"
}
