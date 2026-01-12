# Executor Module

Executes merge and install hooks with proper isolation and strategy dispatch.

## Overview

The executor module is responsible for:
1. Registering builtin and custom hook strategies
2. Building environment variables from ToolConfig
3. Executing hooks in isolated environments
4. Returning structured HookResult contracts

## Public API

### registry.sh

Strategy registration and lookup:

```bash
source "lib/executor/registry.sh"

# Register a builtin strategy
strategy_register "symlink" "builtin_merge_symlink"

# Check if a strategy exists
strategy_exists "symlink"  # returns 0 if exists

# Get strategy function name
fn=$(strategy_get "symlink")  # returns "builtin_merge_symlink"

# List all registered strategies
strategy_list  # outputs one per line
```

### runner.sh

Hook execution with isolated environment:

```bash
source "lib/executor/runner.sh"

# Build environment variables from a resolved ToolConfig
declare -A env_vars
runner_build_env config env_vars

# Execute a hook (builtin or custom)
declare -A result
runner_execute "builtin:symlink" config result
# result is a HookResult contract

# Execute with custom environment
runner_execute_with_env hook_path env_vars result
```

## Builtins

### symlink

Symlinks the last layer to the target path. Supports both file and directory layers.

```bash
source "lib/executor/builtins/symlink.sh"
builtin_merge_symlink config result
```

### concat

Concatenates all layer files into the target, with layer headers.

```bash
source "lib/executor/builtins/concat.sh"
builtin_merge_concat config result
```

### source

Generates a file that sources all layer files (for shell configs).

```bash
source "lib/executor/builtins/source.sh"
builtin_merge_source config result
```

### json-merge

Deep merges JSON files from all layers using jq.

```bash
source "lib/executor/builtins/json-merge.sh"
builtin_merge_json config result
```

## Dependencies

- `core/fs.sh` - Filesystem operations
- `core/log.sh` - Logging
- `core/backup.sh` - Backup before modifications
- `core/errors.sh` - Error codes
- `contracts/tool_config.sh` - ToolConfig contract
- `contracts/hook_result.sh` - HookResult contract

## Contracts

- **Consumes**: ToolConfig (with resolved layer paths)
- **Produces**: HookResult

## Environment Variables

When executing hooks, the following environment variables are set:

| Variable | Description |
|----------|-------------|
| `TOOL` | Tool name (e.g., "git", "nvim") |
| `TARGET` | Absolute target path |
| `LAYERS` | Colon-separated layer names |
| `LAYER_PATHS` | Colon-separated resolved layer paths |
| `DOTFILES_DIR` | Path to dotfiles directory |
| `OS` | Operating system ("darwin" or "linux") |

## Usage Example

```bash
source "lib/executor/registry.sh"
source "lib/executor/runner.sh"

# Initialize filesystem (mock for tests, real for production)
fs_init "real"

# Create and resolve a ToolConfig
declare -A config
tool_config_new config "git" "$HOME/.gitconfig" "builtin:symlink"
tool_config_add_layer config "base" "local" "configs/git"
layer_resolve_tool_config config

# Execute the hook
declare -A result
runner_execute "builtin:symlink" config result

# Check result
if hook_result_is_success result; then
    echo "Success!"
else
    echo "Failed: $(hook_result_get_error_message result)"
fi
```

## Testing

Run tests for this module:

```bash
./test/run_tests.sh unit/executor/
```
