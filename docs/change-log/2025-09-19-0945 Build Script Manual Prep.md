# Build Script Manual Prep

## Goals
- Stop automated XCTest execution so the helper keeps a single simulator session ready for manual verification.
- Keep the simulator boot convenience and clean build steps intact.
- Document the change and validation checklist for future contributors.

## Implementation Plan
1. Update `scripts/build_and_test.sh` to perform `xcodebuild clean build` instead of `clean test`, optionally skipping UI bundles entirely.
2. Preserve the existing simulator-resolution logic and logging while directing outputs into a predictable Derived Data path for later deployment.
3. After the build, install the generated `.app` onto the target simulator and launch it so the UI is immediately visible for manual testing.
4. Ensure the helper exits successfully when the app is running on the simulator.

## Validation Plan
- Run `./scripts/build_and_test.sh` locally and confirm:
  - Only one simulator instance (the target device) is booted.
  - `xcodebuild` completes with a clean build and no test bundles executed.
  - The resulting `.app` is installed on the simulator and launches successfully.
  - The script exits with status 0, leaving the simulator open for manual interaction.

## Outcome
- Script now performs a clean build into a dedicated Derived Data directory, reinstalls the fresh build onto the chosen simulator (removing any prior copy), and launches the app for immediate manual testing.
