# Build & Test Script Automation

## Goals
- Provide a single command to clean build and test the iOS app against the standard iPhone 15 simulator.
- Ensure the simulator is ready for manual validation after the automation completes.
- Document the entry point in the repository README for future contributors.

## Implementation Plan
1. Add a reusable shell script (e.g., `scripts/build_and_test.sh`) with `set -euo pipefail` that:
   - Boots or launches the iPhone 15 simulator.
   - Runs `xcodebuild clean build` for the `MrSaveMySpace` scheme.
   - Executes `xcodebuild test` on the same destination.
2. Mark the script as executable.
3. Update the README to reference the helper script alongside manual invocation instructions.

## Validation Plan
- Manually run the script locally to confirm it boots the simulator and completes build + tests (note: not executed in this environment).
- Monitor script exit codes to ensure the shell terminates on failure via `set -e`.
- Future CI can call the script for consistent reproducibility.
