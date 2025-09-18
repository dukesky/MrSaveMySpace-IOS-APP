# MrSaveMySpace iOS App

MrSaveMySpace helps iPhone users reclaim storage safely by scanning their Photos library, surfacing exact duplicate assets, and providing a swipe-to-triage workflow for manual review. The app is built entirely with SwiftUI and Swift Concurrency targeting iOS 17.5+.

## Getting Started

1. **Prerequisites**
   - Xcode 16 beta 6 or newer (Swift 5.9 toolchain)
   - macOS Sonoma with Simulator runtimes for iOS 17.5
   - Access to a Photos library (Simulator or device) for scanning

2. **Clone & Open**
   ```bash
   git clone https://github.com/dukesky/MrSaveMySpace-IOS-APP.git
   cd MrSaveMySpace-IOS-APP
   open MrSaveMySpace.xcodeproj
   ```

3. **Build**
   ```bash
   xcodebuild -project MrSaveMySpace.xcodeproj \
     -scheme MrSaveMySpace \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     clean build
   ```

4. **Run Tests**
   ```bash
   xcodebuild -project MrSaveMySpace.xcodeproj \
     -scheme MrSaveMySpace \
     -destination 'platform=iOS Simulator,name=iPhone 15' \
     -skip-testing:MrSaveMySpaceUITests test
   ```

## Project Structure

- `MrSaveMySpace/` – application sources (composition root, services, view models, SwiftUI views)
- `docs/design-doc/` – canonical design references (`design_v0.md` consolidates the original Draft v2 requirements and current implementation status)
- `docs/change-log/` – per-request change notes; each future update should add a timestamped Markdown file describing the plan and outcome before code is modified
- `MrSaveMySpaceTests/` – unit tests (currently covers duplicate detector edge cases)
- `MrSaveMySpaceUITests/` – XCUITest harness (smoke templates)

## Working Agreements

- Before starting a new request, ensure the working tree is clean and create a change note in `docs/change-log/` named `YYYY-MM-DD-hhmm Title.md` outlining the design and validation plan.
- Keep commits focused, using imperative commit messages (e.g., “Add swipe deletion prototype”).
- Reference the design doc for architectural expectations (service boundaries, data flow, and UI goals).
- When adding features that touch photo deletion, always surface the space-savings estimate and provide a secondary confirmation.

## Documentation

- [Design Docs](docs/design-doc/design_v0.md)
- [Change Log Index](docs/change-log/)

For additional context on the product roadmap and future modules (similar-photo detection, Live Photo conversion, storage analytics), review the Original Vision section inside `design_v0.md`.

