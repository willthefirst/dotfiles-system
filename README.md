# Dotfiles Layering Framework

A lightweight framework for managing multi-layer dotfiles configurations. Compose configs from multiple sources (personal, work, etc.) with tool-specific merge strategies.

## Why?

Traditional dotfiles setups force you to choose: either maintain separate configs per machine, or clutter personal configs with work-specific settings. This framework solves that by:

- **Layering** - Base configs + overlays (e.g., personal + work)
- **Multi-repo** - Keep public personal configs separate from private work configs
- **Tool-specific merging** - Each tool can use the right strategy (symlink, concat, git includes, etc.)

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Machine Profile (e.g., stripe-mac)                         │
│  Defines: TOOLS=(git zsh nvim) + layer assignments          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  For each tool, resolve layers:                             │
│  nvim_layers=(base stripe)                                  │
│    → base:    ~/.dotfiles/configs/nvim                      │
│    → stripe:  ~/.dotfiles-stripe/nvim                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Run merge hook with layer paths                            │
│  Hook generates final config at target location             │
└─────────────────────────────────────────────────────────────┘
```

## Usage

This framework is designed to be included as a **submodule** in your dotfiles repo:

```bash
# In your dotfiles repo
git submodule add https://github.com/willthefirst/dotfiles-system.git lib/dotfiles-system
```

Then create a wrapper script that invokes it:

```bash
#!/usr/bin/env bash
# install.sh in your dotfiles repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK="${SCRIPT_DIR}/lib/dotfiles-system"
exec "$FRAMEWORK/install.sh" "$@" --dotfiles "$SCRIPT_DIR"
```

See [willthefirst/dotfiles](https://github.com/willthefirst/dotfiles) for a complete example.

## Required Structure

Your dotfiles repo needs:

```
~/.dotfiles/
├── install.sh              # Wrapper script (calls framework)
├── repos.conf              # External repo definitions
├── machines/               # Machine profiles
│   ├── personal-mac.sh
│   └── work-mac.sh
├── tools/                  # Tool configurations
│   └── <tool>/
│       ├── tool.conf       # Layer sources + merge hook
│       └── merge.sh        # Optional custom merge script
├── configs/                # Your actual config files
│   └── <tool>/
└── lib/
    └── dotfiles-system/    # This framework (submodule)
```

## Configuration Files

### Machine Profile (`machines/<name>.sh`)

```bash
TOOLS=(git zsh nvim ssh)

git_layers=(base work)
zsh_layers=(base work)
nvim_layers=(base work)
ssh_layers=(base)  # No work layer for SSH
```

### Tool Config (`tools/<tool>/tool.conf`)

```bash
# Layer sources (local: or REPO_NAME:)
layers_base="local:configs/nvim"
layers_work="WORK_DOTFILES:nvim"

# Target location
target="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"

# Merge strategy
merge_hook="builtin:symlink"  # or ./merge.sh for custom
```

### External Repos (`repos.conf`)

```bash
WORK_DOTFILES="git@github.com:company/dotfiles.git|${HOME}/.dotfiles-work"
```

## Built-in Merge Hooks

| Hook | Description |
|------|-------------|
| `builtin:symlink` | Symlink entire directory (last layer wins) |
| `builtin:concat` | Concatenate files from all layers |
| `builtin:source` | Generate shell file that sources each layer |
| `builtin:json-merge` | Deep merge JSON files |

## Custom Merge Hooks

For complex tools like Neovim, write a custom `merge.sh`:

```bash
#!/usr/bin/env bash
# Environment variables available:
# - TOOL: Tool name
# - LAYERS: Colon-separated layer names
# - LAYER_PATHS: Colon-separated absolute paths
# - TARGET: Target directory
# - OS: darwin/linux
# - MACHINE: Machine profile name

IFS=':' read -ra paths <<< "$LAYER_PATHS"
# ... your merge logic
```

## Utility Functions

The framework provides safe utilities in `lib/utils.sh`:

| Function | Description |
|----------|-------------|
| `safe_expand_vars "$str"` | Expand `${VAR}` without shell injection risk |
| `safe_remove "$path"` | Move file to backup dir before removing |
| `safe_remove_rf "$path"` | Move directory to backup dir before removing |
| `find_config_file "$layer" "$name"` | Find config file in a layer directory |

Backups are stored in `~/.dotfiles-backup/` with timestamps.

## Testing

Run the test suite:

```bash
cd lib/dotfiles-system
./test/run_tests.sh
```

Tests cover:
- Safe variable expansion (injection prevention)
- Safe removal with backups
- Config file discovery
- Tool context management

## License

MIT
