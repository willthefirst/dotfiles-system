# Core Module

Low-level infrastructure used by all other modules.

## Modules

- `errors.sh` - Error codes and handling utilities
- `log.sh` - Logging with configurable output and mock support
- `fs.sh` - Filesystem operations with mock backend for testing
- `backup.sh` - Backup creation and restoration using fs abstraction

## Usage

All modules support dependency injection for testing:

```bash
source "$LIB_DIR/core/fs.sh"
fs_init "mock"  # Use mock backend for tests
fs_init "real"  # Use real filesystem (default)

source "$LIB_DIR/core/log.sh"
declare -A log_config=([output]="mock")
log_init log_config  # Capture logs for testing
```

## Dependencies

- `errors.sh` - No dependencies (leaf module)
- `log.sh` - No dependencies (leaf module)
- `fs.sh` - No dependencies (leaf module)
- `backup.sh` - Depends on: fs.sh, log.sh, errors.sh

## Testing

Run core module tests:

```bash
./test/run_tests.sh unit/core/
```
