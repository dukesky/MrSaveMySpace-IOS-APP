# MrSaveMySpace – Design v0

_Last updated: 2025-09-18_

This document consolidates the original product design for MrSaveMySpace and records the functionality currently implemented in the codebase. Use it as the baseline reference for future feature planning and architectural changes.

---

## 1. Original Design Document (Draft v2)

> **MrSaveMySpace – Design Document (Draft v2)**
>
> ### 1. Project Overview
>
> MrSaveMySpace is envisioned as a one-for-all iPhone storage management app.
>
> **Overall Goals**
>
> A. Clean unnecessary storage → free up large chunks of space (photos, videos, junk files, app caches).
>
> B. Optimize running efficiency → reduce storage bloat that slows down performance.
>
> C. Maximize phone usage → extend battery life, keep storage healthy, ensure long-term usability.
>
> **V1 Focus**
>
> First release targets removing duplicate photos since they are highly storage-consuming.
>
> **Core principles: Easy, Transparent, Safe to use**
>
> Easy: minimal clicks, clear buttons.
>
> Transparent: show what will be deleted, how much space saved.
>
> Safe: deletions always confirmed, recoverable (Recently Deleted).
>
> **Future Goals**
>
> *Short term*
>
> - Similar photo detection (choose the best, remove others).
>
> - Convert Live Photos to stills to save space.
>
> *Long term*
>
> - File management (documents, downloads, caches).
>
> - App management (large unused apps, cache cleaners).
>
> - Battery management (usage analytics + optimization tips).
>
> ### 2. Tech Stack
>
> - **Language:** Swift 5.9+
> - **UI Framework:** SwiftUI
> - **System Frameworks:**
>   - PhotoKit (Photos, PHPhotoLibrary, PHAsset)
>   - UIKit/UIImage
>   - Vision (future M3+)
> - **Hashing:** dHash (64-bit perceptual hash)
> - **Persistence:** JSON index in app’s Documents directory
> - **Concurrency:** Swift Concurrency (async/await, TaskGroup)
> - **Scalability:** Modularized feature services for plug-in modules (file cleaner, battery optimizer, etc.)
>
> ### 3. App Architecture
>
> Pattern: MVVM-light + modular features
>
> **High-Level Layers**
>
> - **Model Layer** – Fingerprint, DuplicateGroup, PhotoStats
> - **Services Layer** – PhotoLibraryManager, PhotoScanner, DuplicateDetector, DeletionManager (+ Future services)
> - **ViewModel Layer** – AppModel, ResultsViewModel
> - **UI Layer** – ContentView, ScanView, ResultsView (+ Future views)
>
> **Rough File Structure**
>
> ```text
> MrSaveMySpace/
> ├─ MrSaveMySpace.xcodeproj
> ├─ MrSaveMySpace/
> │  ├─ App/
> │  ├─ Features/
> │  ├─ Models/
> │  └─ UI/
> └─ Info.plist
> ```
>
> ### 4. UI Design Goals
>
> - Easy to use, clear to understand.
> - Primary screens: Fast Detection, Swipe Deletion, Similar Photos (future), Photo Analysis (future).
>
> ### 5. Milestones
>
> - **M1 – Duplicate Indexing:** permissions, scanning, hashing, JSON index, progress UI.
> - **M2 – Exact Duplicates Detection:** grouping, results UI, deletion flow, space-savings estimate.
> - **Future Milestones:** Similar photos, conversion, full storage manager.
>
> ### 6. Data Flow
>
> 1. Trigger scan from UI → AppModel → PhotoScanner.
> 2. Build fingerprints index → JSONStore.
> 3. Duplicate detection → DuplicateDetector → results UI.
> 4. Deletion → DeletionManager → PhotoLibrary.
>
> ### 7. Data Structures
>
> Defines `Fingerprint`, `DuplicateGroup`, and future `PhotoStats` models.
>
> ### 8. Risks & Mitigations
>
> - Hash collisions → validate with dimensions / perceptual distance.
> - iCloud-only assets → estimate size from resolution.
> - Performance → hash maps, batching.
> - User trust → previews, estimates, Recently Deleted safety net.
>
> ### 9. Next Steps
>
> - Implement M1 + M2.
> - Build ResultsView with duplicate groups.
> - Add Fast Detection entry point.
> - Prepare hooks for future modules (Similar, Conversion, Analysis).

---

## 2. Implementation Snapshot (as of 2025-09-18)

### 2.1 Feature Coverage

| Area | Status | Notes |
| --- | --- | --- |
| Permissions & Scanning (M1) | ✅ Completed | `ScanViewModel` and `PhotoScanner` handle incremental hashing with progress reporting. JSON index stored under Documents. |
| Duplicate Detection (M2) | ✅ Completed | `DuplicateDetector` groups by dHash + dimensions + creation-time proximity; `ResultsViewModel` estimates per-photo sizes and total savings. |
| Deletion Flow | ✅ Completed | `DeletionManager` wraps `PHPhotoLibrary.performChanges`. Results UI provides confirmation dialog and status messaging. |
| Transparency Enhancements | ✅ Completed | Results list shows per-photo IDs, estimated bytes, and live thumbnail previews. |
| Swipe Deletion (prototype) | ✅ Completed | New “Swipe Deletion” tool offers month-by-month review with Tinder-style keep/delete gestures, undo, and bulk delete. |
| Testing | ⚠️ Partial | Core duplicate detector has unit coverage. No UI/unit tests yet for swipe flow or scanning pipeline beyond template stubs. |
| Project Structure | ⚠️ Needs follow-up | Source currently flattened into `AppModel.swift` and `ContentView.swift`. Re-modularization back into `App/`, `Features/`, `UI/` is pending once Xcode project references are realigned. |

### 2.2 Architecture in Code

- `AppModel.swift` acts as the composition root: it owns the PhotoKit services, exposes scan/results/swipe view models, and centralizes deletion updates.
- Service layer (PhotoLibraryManager, PhotoScanner, StorageEstimator, DuplicateDetector) remains focused on PhotoKit orchestration and data enrichment.
- Swipe deletion relies on two view models:
  - `SwipeDeletionViewModel` aggregates `PHAsset`s into month buckets.
  - `SwipeMonthDetailViewModel` drives the Tinder-style interaction, caching thumbnails, tracking keeps/deletes, and executing batched deletions.
- SwiftUI integrates the flows in `ContentView.swift` with subviews for scanning, duplicates, and swipe deletion. The results views use safe-area insets for persistent action bars and leverage async image loading.

### 2.3 Known Gaps & Next Steps

1. **Source Layout:** restore logical folders (`App/`, `Features/`, `Models/`, `UI/`) and update project references to match the documented architecture.
2. **Additional Tests:** add unit coverage for scan progress, storage estimator fallbacks, and swipe decision logic; introduce a lightweight UI test for the swipe flow once automation hooks are ready.
3. **Future Features:** prepare extension points for similar-photo detection, Live Photo conversion, and broader storage tools per the design roadmap.
4. **User Trust Enhancements:** consider surfacing actual thumbnails and deletion summaries in confirmation dialogs, plus secondary confirmations for bulk deletes.

### 2.4 Tooling & Commands

- Build: `xcodebuild -project MrSaveMySpace.xcodeproj -scheme MrSaveMySpace -destination 'platform=iOS Simulator,name=iPhone 15' clean build`
- Tests: `xcodebuild -project MrSaveMySpace.xcodeproj -scheme MrSaveMySpace -destination 'platform=iOS Simulator,name=iPhone 15' -skip-testing:MrSaveMySpaceUITests test`
- Fingerprint index stored at `~/Library/Developer/CoreSimulator/Devices/.../Documents/photo_fingerprints.json` (via `Paths.fingerprintsURL()`).

---

## 3. Revision History

| Version | Date | Summary |
| --- | --- | --- |
| v0 | 2025-09-18 | Initial consolidation of Draft v2 design with implementation snapshot covering scanning, duplicate removal, and swipe deletion prototype. |

