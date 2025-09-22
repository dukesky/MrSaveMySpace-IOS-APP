# Build Script Simulator Fix

## Goals
- Prevent multiple Simulator windows from launching when running `scripts/build_and_test.sh`.
- Ensure the helper script reuses a single booted simulator instance and avoids redundant launches.
- Keep README usage instructions accurate after adjustments.

## Implementation Plan
1. Investigate the current script to identify duplicate simulator boot triggers (e.g., multiple `xcodebuild` invocations and broad destination selectors).
2. Update the build script to:
   - Resolve a concrete simulator UDID for `iPhone 15 (17.5)` via `xcrun simctl list --json` (parsed with `python3`) and reuse it for all commands, falling back to the first available runtime for that device if the default OS is missing. Fallback grep-based parsing remains for environments without Python or when JSON parsing fails.
   - Collapse the separate build/test invocations into a single `xcodebuild clean test` call.
   - Only open the Simulator app when not already running, if necessary.
3. Adjust logging to reflect the refined behavior.
4. Update README wording if command behavior changes.

## Validation Plan
- Run the modified script locally to confirm only one simulator launches and the command completes successfully (manual verification by the developer).
- Optionally use `scripts/stop_tests.sh` after execution to ensure environment resets cleanly.

## Outcome
- Script now resolves the UDID for `iPhone 15` (preferring iOS 17.5, otherwise the first available runtime) using the JSON API so Xcode reuses the same device instead of cloning copies, with a grep fallback when Python isn’t available or JSON parsing fails.
- Updated the helper to avoid `mapfile` (unavailable on macOS’s default Bash 3.2) by using command substitutions and explicit parsing instead.
- Collapsed build/test into one `xcodebuild clean test` invocation and added guards to avoid reopening Simulator when already running.
- Updated README instructions to reflect the refined behavior.
