# Auto Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Releases based update checking, downloading, and macOS installer launch support to SnapFlow.

**Architecture:** Create one focused updater service in `SnapFlowExample` and keep UI decisions in `AppDelegate`. The updater owns GitHub JSON parsing, version comparison, asset selection, downloading, and opening installers; tests cover pure logic without network calls.

**Tech Stack:** Swift 5, AppKit, Foundation `URLSession`, XCTest, GitHub Releases REST API.

## Global Constraints

- Keep macOS app deployment target at `10.15`.
- Do not add third-party dependencies.
- Do not silently overwrite a running `SnapFlow.app`.
- Startup check failures stay silent; manual check failures use alerts.
- Prefer `.pkg`, then `.dmg`, then `.zip` release assets.

---

### Task 1: Updater Pure Logic

**Files:**
- Create: `SnapFlowExample/GitHubReleaseUpdater.swift`
- Create: `SnapFlowTests/GitHubReleaseUpdaterTests.swift`
- Modify: `SnapFlow.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `struct AppVersion: Comparable`
- Produces: `struct GitHubReleaseAsset: Decodable`
- Produces: `struct GitHubRelease: Decodable`
- Produces: `final class GitHubReleaseUpdater`
- Produces: `GitHubReleaseUpdater.bestInstallerAsset(from:) -> GitHubReleaseAsset?`
- Produces: `GitHubReleaseUpdater.isRemoteVersion(_:newerThan:) -> Bool`

- [ ] **Step 1: Write failing tests for version comparison and asset selection**

Add tests that assert `v0.2.1` is newer than `0.2.0`, equal to `0.2.1`, older than `1.0.0`, and that `.pkg` beats `.dmg`, which beats `.zip`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowTests test`

Expected: FAIL because `GitHubReleaseUpdater` does not exist.

- [ ] **Step 3: Implement pure updater models and comparison helpers**

Create `GitHubReleaseUpdater.swift` with decodable release models, `AppVersion`, and asset ranking helpers.

- [ ] **Step 4: Add new Swift files to app and test targets**

Update `SnapFlow.xcodeproj/project.pbxproj` so `GitHubReleaseUpdater.swift` is compiled into `SnapFlowExample` and `SnapFlowTests`, and `GitHubReleaseUpdaterTests.swift` is compiled into `SnapFlowTests`.

- [ ] **Step 5: Run tests**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowTests test`

Expected: PASS.

### Task 2: Network Download and Installation Launch

**Files:**
- Modify: `SnapFlowExample/GitHubReleaseUpdater.swift`
- Test: `SnapFlowTests/GitHubReleaseUpdaterTests.swift`

**Interfaces:**
- Consumes: `GitHubReleaseUpdater.bestInstallerAsset(from:)`
- Produces: `GitHubReleaseUpdater.checkForUpdate(completion:)`
- Produces: `GitHubReleaseUpdater.downloadAndOpenInstaller(for:completion:)`

- [ ] **Step 1: Add completion result types**

Add `UpdateCheckResult` for `.upToDate` and `.updateAvailable(release:asset:)`, plus `UpdaterError` for invalid responses, missing assets, and download failures.

- [ ] **Step 2: Implement latest release fetch**

Use `URLSession.shared.dataTask` against `https://api.github.com/repos/Crazy-MT/SnapFlow/releases/latest`, decode `GitHubRelease`, compare versions, and return on the main queue.

- [ ] **Step 3: Implement download**

Download the selected `browser_download_url` into `~/Downloads`, replacing any existing file with the same name.

- [ ] **Step 4: Implement installer opening**

Open `.pkg` through `NSWorkspace.shared.open`. Mount `.dmg` with `/usr/bin/hdiutil attach -nobrowse`, then open a `.pkg` inside the mounted volume if present, otherwise reveal a contained `.app` or the mounted volume. Open `.zip` with `NSWorkspace.shared.open`.

- [ ] **Step 5: Run tests**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowTests test`

Expected: PASS.

### Task 3: AppDelegate Integration

**Files:**
- Modify: `SnapFlowExample/AppDelegate.swift`

**Interfaces:**
- Consumes: `GitHubReleaseUpdater.checkForUpdate(completion:)`
- Consumes: `GitHubReleaseUpdater.downloadAndOpenInstaller(for:completion:)`

- [ ] **Step 1: Add updater property**

Add `private let updater = GitHubReleaseUpdater()` to `AppDelegate`.

- [ ] **Step 2: Add menu item**

Add `Check for Updates...` above `Quit` in the status menu.

- [ ] **Step 3: Add startup check**

Call a quiet updater check after launch. If an update exists, present an alert asking the user to download and install.

- [ ] **Step 4: Add manual check action**

Manual checks show up-to-date, failure, and update-available alerts.

- [ ] **Step 5: Build app**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowExample build`

Expected: BUILD SUCCEEDED.

### Task 4: Final Verification

**Files:**
- Verify: `SnapFlowExample/GitHubReleaseUpdater.swift`
- Verify: `SnapFlowExample/AppDelegate.swift`
- Verify: `SnapFlowTests/GitHubReleaseUpdaterTests.swift`

- [ ] **Step 1: Run unit tests**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowTests test`

Expected: PASS.

- [ ] **Step 2: Run app build**

Run: `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowExample build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Check git diff**

Run: `git diff --stat`

Expected: only updater, tests, project, and superpowers docs changed.
