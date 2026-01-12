# JSON Configuration Schemas

This directory contains JSON Schema definitions for all dotfiles configuration files. These schemas provide:

- **Validation**: Ensure configs are correctly structured
- **IDE Support**: Autocomplete and inline documentation in editors like VS Code
- **Documentation**: Formal specification of all configuration options

## Schema Files

| Schema | Purpose | Used By |
|--------|---------|---------|
| `tool.schema.json` | Tool configuration | `tools/*/tool.json` |
| `repos.schema.json` | External repository definitions | `repos.json` |
| `machine.schema.json` | Machine profile configuration | `machines/*.json` |

## Using Schemas in JSON Files

Add a `$schema` property at the top of your JSON file to enable IDE support:

```json
{
  "$schema": "../../lib/dotfiles-system/schemas/tool.schema.json",
  "target": "~/.gitconfig",
  ...
}
```

Path is relative from the JSON file to the schema file.

## Schema Overview

### tool.schema.json

Defines tool configuration with layers, target path, and hooks.

**Required fields:**
- `target` - Installation path (use `~` for home)
- `layers` - Array of layer definitions with `name`, `source`, and `path`
- `merge_hook` - How to merge layers (`builtin:*` or script path)

**Optional fields:**
- `install_hook` - Script to install dependencies
- `env` - Environment variables for hooks

**Example:**
```json
{
  "$schema": "../../lib/dotfiles-system/schemas/tool.schema.json",
  "target": "~/.gitconfig",
  "layers": [
    { "name": "base", "source": "local", "path": "configs/git" },
    { "name": "stripe", "source": "STRIPE_DOTFILES", "path": "git" }
  ],
  "merge_hook": "./merge.sh",
  "install_hook": "./install.sh"
}
```

**Built-in merge hooks:**
- `builtin:source` - Generate shell file that sources each layer
- `builtin:concat` - Concatenate layer files (e.g., SSH config)
- `builtin:symlink` - Symlink directory (single layer only)
- `builtin:json-merge` - Deep merge JSON files

### repos.schema.json

Defines external repositories that provide configuration layers.

**Required fields:**
- `repositories` - Array of repository definitions

**Repository properties:**
- `name` - Identifier used in tool layers (UPPER_SNAKE_CASE)
- `url` - Git clone URL
- `path` - Local clone path (use `~` for home)

**Example:**
```json
{
  "$schema": "lib/dotfiles-system/schemas/repos.schema.json",
  "repositories": [
    {
      "name": "STRIPE_DOTFILES",
      "url": "git@git.corp.stripe.com:willm/dotfiles-stripe.git",
      "path": "~/.dotfiles-stripe"
    }
  ]
}
```

### machine.schema.json

Defines machine profiles specifying which tools and layers to install.

**Required fields:**
- `name` - Profile identifier (matches filename)
- `tools` - Map of tool names to layer arrays

**Optional fields:**
- `description` - Human-readable description

**Example:**
```json
{
  "$schema": "../lib/dotfiles-system/schemas/machine.schema.json",
  "name": "stripe-mac",
  "description": "Stripe Mac configuration - base + stripe layers",
  "tools": {
    "git": ["base", "stripe"],
    "zsh": ["base", "stripe"],
    "nvim": ["base", "stripe"],
    "ssh": ["base", "stripe"],
    "ghostty": ["base"],
    "karabiner": ["base"],
    "claude": ["base"],
    "vscode": ["base", "stripe"]
  }
}
```

## Layer Priority

Layers are applied in array order:
- First layer = lowest priority (base configuration)
- Last layer = highest priority (overrides previous layers)

This allows base configurations to be overridden by environment-specific layers (e.g., work settings override personal defaults).

## Path Conventions

- Use `~` for home directory paths (expanded at runtime)
- Do not use `${HOME}` or `$HOME` in JSON files
- Paths in `layers[].path` are relative to the source repository root

## Validation

Validate JSON files against schemas using `jq` or an online validator:

```bash
# Basic JSON syntax check
jq . tools/git/tool.json

# Full schema validation (requires ajv-cli or similar)
npx ajv validate -s lib/dotfiles-system/schemas/tool.schema.json -d tools/git/tool.json
```
