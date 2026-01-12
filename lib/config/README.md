# Config Module

Configuration parsing and validation for tool.conf files and machine profiles.

## Overview

This module handles all configuration loading:
- **parser.sh**: Parses tool.conf files into raw key-value pairs
- **validator.sh**: Converts raw config to validated ToolConfig contracts
- **machine.sh**: Loads machine profiles into MachineConfig contracts

All functions use the `fs` abstraction for testability via mocking.

## Public API

### parser.sh

```bash
config_parse_tool_conf(tool_dir, result_ref)
    Parse a tool.conf file into raw key-value associative array.

    Parameters:
      tool_dir   - Directory containing tool.conf (e.g., "/path/to/tools/git")
      result_ref - Nameref to associative array for output

    Output keys:
      target       - Target path (required)
      merge_hook   - Merge hook specification (required)
      install_hook - Install hook (optional)
      layers_*     - Layer definitions (e.g., layers_base="local:configs/git")

    Returns: E_OK, E_NOT_FOUND, or E_VALIDATION
```

### validator.sh

```bash
config_build_tool_config(raw_ref, tool_config_ref, tool_dir)
    Convert raw parsed config to validated ToolConfig contract.

    Parameters:
      raw_ref         - Nameref to raw config from parser
      tool_config_ref - Nameref to output ToolConfig
      tool_dir        - Tool directory (for tool_name extraction)

    Returns: E_OK or E_VALIDATION (errors to stderr)

config_resolve_hook_path(hook, tool_dir)
    Resolve a hook specification to its full path.
    Handles builtin:* hooks and relative paths.

    Outputs: Resolved hook string to stdout
```

### machine.sh

```bash
config_load_machine_profile(profile_path, result_ref)
    Load a machine profile into MachineConfig contract.

    Parameters:
      profile_path - Path to profile script (e.g., "machines/stripe-mac.sh")
      result_ref   - Nameref to MachineConfig for output

    Returns: E_OK, E_NOT_FOUND, or E_VALIDATION

config_get_profile_name(profile_path)
    Extract profile name from path.

    Example: "machines/stripe-mac.sh" -> "stripe-mac"
```

## Dependencies

- `core/fs.sh` - Filesystem operations (for mock support)
- `core/errors.sh` - Error codes
- `contracts/tool_config.sh` - ToolConfig contract
- `contracts/machine_config.sh` - MachineConfig contract

## Contracts

- **Produces**: ToolConfig, MachineConfig
- **Consumes**: Raw key-value data from tool.conf files

## File Formats

### tool.conf Format

```bash
# Comment lines start with #
target="${HOME}/.gitconfig"        # Required: target path
merge_hook="builtin:symlink"       # Required: merge strategy
install_hook="./install.sh"        # Optional: install script

# Layer definitions: layers_{name}="source:path"
layers_base="local:configs/git"
layers_stripe="STRIPE_DOTFILES:git"
```

**Sources**:
- `local` - Relative to DOTFILES_DIR
- `REPO_NAME` - External repo (uppercase, e.g., STRIPE_DOTFILES)

### Machine Profile Format

```bash
# Array of tools to configure
TOOLS=(git zsh nvim)

# Layer assignments per tool
git_layers=(base stripe)
zsh_layers=(base)
nvim_layers=(base stripe)
```

## Usage Example

```bash
source "$LIB_DIR/config/parser.sh"
source "$LIB_DIR/config/validator.sh"
source "$LIB_DIR/config/machine.sh"

# Parse a tool config
declare -A raw_config
config_parse_tool_conf "/path/to/tools/git" raw_config || exit $?

# Convert to validated ToolConfig
declare -A tool_config
config_build_tool_config raw_config tool_config "/path/to/tools/git" || exit $?

# Load machine profile
declare -A machine_config
config_load_machine_profile "/path/to/machines/stripe-mac.sh" machine_config || exit $?
```

## Testing

```bash
# Run all config tests
./lib/dotfiles-system/test/run_tests.sh unit/config/

# Run specific test
./lib/dotfiles-system/test/run_tests.sh unit/config/test_parser.sh
```
