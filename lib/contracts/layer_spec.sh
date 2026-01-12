#!/usr/bin/env bash
# CONTRACT: LayerSpec
# PURPOSE: Layer specification data structure and validation
#
# A LayerSpec represents a single configuration layer that contributes
# to a tool's final configuration. Layers can come from local directories
# or external repositories.
#
# PUBLIC API:
#   layer_spec_new(result_ref, name, source, path)
#       Create a new LayerSpec. Result stored in associative array.
#
#   layer_spec_validate(spec_ref)
#       Validate a LayerSpec. Returns E_OK or E_VALIDATION.
#       On failure, writes errors to stderr.
#
#   layer_spec_set_resolved(spec_ref, resolved_path)
#       Set the resolved absolute path after layer resolution.
#
#   layer_spec_get_name(spec_ref)      - Get layer name
#   layer_spec_get_source(spec_ref)    - Get source type
#   layer_spec_get_path(spec_ref)      - Get relative path
#   layer_spec_get_resolved(spec_ref)  - Get resolved absolute path
#
# DEPENDENCIES: core/errors.sh

[[ -n "${_CONTRACT_LAYER_SPEC_LOADED:-}" ]] && return 0
_CONTRACT_LAYER_SPEC_LOADED=1

# Source dependencies
_CONTRACT_LAYER_SPEC_DIR="${BASH_SOURCE[0]%/*}"
source "$_CONTRACT_LAYER_SPEC_DIR/../core/errors.sh"

# Create a new LayerSpec
# Usage: layer_spec_new result "base" "local" "configs/git"
layer_spec_new() {
    local -n __ls_result=$1
    local name="$2"
    local source="$3"
    local path="$4"

    __ls_result=(
        [name]="$name"
        [source]="$source"
        [path]="$path"
        [resolved_path]=""
    )
}

# Validate a LayerSpec
# Returns: E_OK if valid, E_VALIDATION if not (with errors to stderr)
layer_spec_validate() {
    local -n __ls_spec=$1
    local errors=()

    # Required fields
    [[ -z "${__ls_spec[name]:-}" ]] && errors+=("name is required")
    [[ -z "${__ls_spec[source]:-}" ]] && errors+=("source is required")
    [[ -z "${__ls_spec[path]:-}" ]] && errors+=("path is required")

    # Validate name format: alphanumeric, hyphens, underscores
    local name="${__ls_spec[name]:-}"
    if [[ -n "$name" && ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        errors+=("name must be alphanumeric with hyphens/underscores: $name")
    fi

    # Validate source: must be "local" or UPPERCASE_IDENTIFIER (repo name)
    local src="${__ls_spec[source]:-}"
    if [[ -n "$src" ]]; then
        if [[ "$src" != "local" && ! "$src" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
            errors+=("source must be 'local' or REPO_NAME (uppercase): $src")
        fi
    fi

    # Validate path: must not be empty, must not start with /
    local path="${__ls_spec[path]:-}"
    if [[ -n "$path" && "$path" == /* ]]; then
        errors+=("path must be relative, not absolute: $path")
    fi

    # Report errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        printf 'LayerSpec validation failed:\n' >&2
        printf '  - %s\n' "${errors[@]}" >&2
        return $E_VALIDATION
    fi

    return $E_OK
}

# Set the resolved absolute path
layer_spec_set_resolved() {
    local -n __ls_spec=$1
    __ls_spec[resolved_path]="$2"
}

# Getters
layer_spec_get_name() {
    local -n __ls_spec=$1
    printf '%s' "${__ls_spec[name]:-}"
}

layer_spec_get_source() {
    local -n __ls_spec=$1
    printf '%s' "${__ls_spec[source]:-}"
}

layer_spec_get_path() {
    local -n __ls_spec=$1
    printf '%s' "${__ls_spec[path]:-}"
}

layer_spec_get_resolved() {
    local -n __ls_spec=$1
    printf '%s' "${__ls_spec[resolved_path]:-}"
}
