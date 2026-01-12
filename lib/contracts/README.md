# Contracts Module

Defines data structures and validation for all module boundaries.

## Philosophy

Contracts are the "types" of our bash system. Every function that crosses
a module boundary should:

1. Accept data conforming to a contract
2. Validate input at entry
3. Return data conforming to a contract

This enables:
- **Fail-fast**: Invalid data detected immediately with clear errors
- **Testability**: Contracts can be validated without I/O
- **Documentation**: Contracts serve as executable documentation

## Contracts

### LayerSpec

Represents a single configuration layer.

```bash
source "$LIB_DIR/contracts/layer_spec.sh"

declare -A layer
layer_spec_new layer "base" "local" "configs/git"
layer_spec_validate layer || exit 1
layer_spec_set_resolved layer "/home/user/.dotfiles/configs/git"
```

Fields:
- `name` (required): Layer name (e.g., "base", "stripe", "work")
- `source` (required): Source type - "local" or repo name like "STRIPE_DOTFILES"
- `path` (required): Relative path within source
- `resolved_path` (computed): Absolute path after resolution

### ToolConfig

Represents a parsed and validated tool configuration.

```bash
source "$LIB_DIR/contracts/tool_config.sh"

declare -A config
tool_config_new config "git" "$HOME/.gitconfig" "builtin:symlink"
tool_config_add_layer config "base" "local" "configs/git"
tool_config_validate config || exit 1
```

Fields:
- `tool_name` (required): Tool identifier (e.g., "git", "nvim")
- `target` (required): Absolute path to installation target
- `merge_hook` (required): Hook specification ("builtin:*" or script path)
- `install_hook` (optional): Install hook specification
- `layer_count` (computed): Number of layers
- `layer_N_name`, `layer_N_source`, `layer_N_path` (computed): Layer data

### MachineConfig

Represents a loaded machine profile.

```bash
source "$LIB_DIR/contracts/machine_config.sh"

declare -A machine
machine_config_new machine "work-macbook"
machine_config_add_tool machine "git"
machine_config_set_tool_layers machine "git" "base work"
machine_config_validate machine || exit 1
```

Fields:
- `profile_name` (required): Profile identifier
- `tool_count` (computed): Number of tools
- `tool_N` (computed): Tool name at index N
- `layers_TOOLNAME` (computed): Space-separated layer names for tool

### HookResult

Represents the result of hook execution.

```bash
source "$LIB_DIR/contracts/hook_result.sh"

declare -A result
hook_result_new result 1  # success=true
hook_result_validate result || exit 1

# Or for failure:
hook_result_new_failure result $E_PERMISSION "Cannot write to target"
```

Fields:
- `success` (required): "1" for success, "0" for failure
- `error_code` (optional): Error code if failed
- `error_message` (optional): Human-readable error message
- `files_modified` (optional): Space-separated list of modified paths

## Dependencies

All contracts depend on:
- `core/errors.sh` - Error codes (E_OK, E_VALIDATION)

Contracts have **no filesystem dependencies** - they are pure data validation.

## Usage Pattern

```bash
# 1. Create contract instance
declare -A config
tool_config_new config "git" "$HOME/.gitconfig" "builtin:symlink"

# 2. Populate additional fields
tool_config_add_layer config "base" "local" "configs/git"

# 3. Validate before use
if ! tool_config_validate config; then
    echo "Invalid config" >&2
    exit 1
fi

# 4. Pass to other modules
process_tool config
```

## Testing

Run contract tests:

```bash
./test/run_tests.sh unit/contracts/
```
