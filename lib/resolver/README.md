# Resolver Module

Resolves layer specifications to absolute paths, handles path expansion, and manages external repositories.

## Overview

The resolver module transforms relative layer specifications (like `"local:configs/git"` or `"STRIPE_DOTFILES:git"`) into absolute filesystem paths. It handles:

- Path expansion (`~`, environment variables)
- Local layer resolution (relative to DOTFILES_DIR)
- External repository path resolution
- Repository existence checking and cloning

## Modules

### `paths.sh` - Path Expansion

Pure string manipulation for path expansion.

```bash
source "lib/resolver/paths.sh"

# Expand ~ to $HOME
path_expand_tilde "~/.config"  # -> /home/user/.config

# Expand environment variables
path_expand_env_vars '${HOME}/.config'  # -> /home/user/.config

# Resolve relative to a base directory
path_resolve_relative "configs/git" "/path/to/dotfiles"  # -> /path/to/dotfiles/configs/git

# Full path expansion (tilde + env vars)
path_expand "~/.config/${USER}"  # -> /home/user/.config/user
```

### `repos.sh` - Repository Management

Manages external repository configuration and operations.

```bash
source "lib/resolver/repos.sh"

# Initialize with dotfiles directory
repos_init "/path/to/dotfiles"

# Get repository path
repos_get_path "STRIPE_DOTFILES"  # -> /path/to/stripe-dotfiles

# Check if repo exists locally
repos_exists "STRIPE_DOTFILES"  # returns 0 or 1

# Ensure repository is cloned
repos_ensure "STRIPE_DOTFILES"

# Get all configured repos
repos_list  # -> "STRIPE_DOTFILES WORK_DOTFILES"
```

### `layers.sh` - Layer Resolution

Resolves layer specifications to absolute paths using paths.sh and repos.sh.

```bash
source "lib/resolver/layers.sh"

# Initialize resolver
layer_resolver_init "/path/to/dotfiles"

# Resolve a single layer spec
layer_resolve_spec "local:configs/git"  # -> /path/to/dotfiles/configs/git
layer_resolve_spec "STRIPE_DOTFILES:git"  # -> /external/stripe-dotfiles/git

# Resolve all layers in a ToolConfig
declare -A config
tool_config_new config "git" "~/.gitconfig" "builtin:symlink"
tool_config_add_layer config "base" "local" "configs/git"
tool_config_add_layer config "work" "STRIPE_DOTFILES" "git"

layer_resolve_tool_config config  # Sets resolved_path for each layer
```

## Dependencies

- `core/fs.sh` - Filesystem operations (for checking paths)
- `core/errors.sh` - Error codes
- `contracts/tool_config.sh` - ToolConfig contract (for layer resolution)

## Error Handling

All functions return error codes from `core/errors.sh`:

| Code | Constant | Description |
|------|----------|-------------|
| 0 | E_OK | Success |
| 2 | E_INVALID_INPUT | Invalid path or layer spec |
| 3 | E_NOT_FOUND | Repository or directory not found |
| 6 | E_DEPENDENCY | Git not available for clone |

## Testing

```bash
# Run all resolver tests
./test/run_tests.sh unit/resolver/

# Run specific test file
./test/run_tests.sh unit/resolver/test_paths.sh
./test/run_tests.sh unit/resolver/test_repos.sh
./test/run_tests.sh unit/resolver/test_layers.sh
```

## Design Notes

1. **Pure vs Effectful**: `paths.sh` is pure (no I/O), `repos.sh` has side effects (git, filesystem)
2. **Testability**: All modules use mock filesystem via `fs_init "mock"`
3. **No Global State**: Functions receive explicit inputs, return explicit outputs
4. **Fail Fast**: Invalid input detected early with clear error messages
