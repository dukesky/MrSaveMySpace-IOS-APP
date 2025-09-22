# Repository Guidelines

## Project Structure & Module Organization
The Xcode project is defined in `MrSaveMySpace.xcodeproj`, with runtime sources under `MrSaveMySpace/`. Use `App/` for application entry points, `Features/` for user-facing modules, and `UI/` for reusable SwiftUI components. Persisted models live beside `Persistence.swift`, while design assets stay in `Assets.xcassets` and preview data in `Preview Content/`. Core Data entities reside in `MrSaveMySpace.xcdatamodeld`. Unit tests live in `MrSaveMySpaceTests/`, and UI smoke tests in `MrSaveMySpaceUITests/`.

## Build, Test, and Development Commands
Run a clean simulator build headlessly with:
```bash
xcodebuild -project MrSaveMySpace.xcodeproj -scheme MrSaveMySpace \
  -destination 'platform=iOS Simulator,name=iPhone 15' clean build
```
Execute XCTest (unit + UI) on the same destination:
```bash
xcodebuild -project MrSaveMySpace.xcodeproj -scheme MrSaveMySpace \
  -destination 'platform=iOS Simulator,name=iPhone 15' test
```
When iterating in Xcode, select the `MrSaveMySpace` scheme and target the latest iPhone simulator to match CI expectations.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: `UpperCamelCase` for types, `lowerCamelCase` for properties and functions, and verb-led method names. Use four-space indentation and keep braces on the same line as declarations, consistent with current files. Prefer structuring SwiftUI views with small, composable structs placed within their feature directory. Group file sections with `// MARK:` comments when a file grows larger than one screen.

## Testing Guidelines
Use XCTest for both unit and UI layers. Name tests with intent-revealing `testWhen_doExpect()` patterns, mirroring the default templates in `MrSaveMySpaceTests.swift`. Keep fixtures lightweight and favor dependency injection over global state. Run `xcodebuild … test` before submitting changes and add UI assertions in `MrSaveMySpaceUITests` for flows that touch navigation or Core Data. Target at least smoke coverage for new features and add regression tests when fixing bugs.

## Commit & Pull Request Guidelines
Write commits as concise, imperative sentences (e.g., "Add trash selection reducer"), avoiding generic messages like "update" seen in earlier history. Scope each commit to a reviewable change and run tests beforehand. Pull requests should describe the user-facing impact, list test evidence (command output or simulator screenshots for UI), and link related issues or Linear tickets. Mention any schema or entitlement adjustments so reviewers can validate provisioning impacts.
