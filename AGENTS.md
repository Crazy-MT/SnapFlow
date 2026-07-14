# Repository Guidelines

## Project Structure & Module Organization

This repository is a macOS application. It is no longer distributed as a reusable keyboard-shortcuts library; the shortcut code is kept as an internal implementation detail of the app.

- `SnapFlowExample/` is the macOS app itself — status bar, search panel, clipboard history, PasteFlow, and the three configurable shortcut actions.
- `Sources/SnapFlowKit/` is the app's internal global-shortcut implementation (shortcut models, Carbon integration, SwiftUI/Cocoa recorders, menu-item helpers). Kept as an internal Swift Package target so `swift build` can compile it in isolation.
- `SnapFlowTests/` contains XCTest coverage for shortcut persistence, clipboard history, search, and PasteFlow detection.
- `SnapFlow.xcodeproj/` contains the shared schemes for the app and tests.
- `logo.png`, `screenshot.png`, and `readme.md` are documentation assets.

## Build, Test, and Development Commands

- `swift build` builds the internal `SnapFlowKit` target declared in `Package.swift`.
- `open SnapFlow.xcodeproj` opens the Xcode project for running the app.
- `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowExample build` builds the app.
- `xcodebuild -project SnapFlow.xcodeproj -scheme SnapFlowTests test` runs the XCTest target.
- `swiftlint` runs the same linter configured by `.swiftlint.yml` and CI.

## Coding Style & Naming Conventions

Follow `.editorconfig`: use tabs for Swift and project files, LF line endings, UTF-8, final newlines, and no trailing whitespace. YAML files use two-space indentation.

Swift code should satisfy the rules in `.swiftlint.yml`. Prefer concise APIs and existing naming patterns such as `SnapFlowKit.Name`, `Shortcut`, `Recorder`, and `RecorderCocoa`. Keep macOS compatibility at `10.11` unless the deployment target is intentionally changed.

## Testing Guidelines

Tests use XCTest and live in `SnapFlowTests/`. Name tests with the `test...` prefix, and keep each test focused on one behavior. Reset shared state, especially `UserDefaults`, in setup before testing shortcut persistence. Add tests for changes to serialization, defaults, shortcut reset behavior, and app logic (clipboard history, search, PasteFlow detection) when practical.

## Commit & Pull Request Guidelines

Recent commits use short, direct subjects, often in Chinese, for example `调整界面` or `快捷键打开指定app或脚本`. Keep commit messages imperative and scoped to the change.

Pull requests should include a concise summary, test results or manual verification steps, linked issues when relevant, and screenshots or recordings for UI changes in `SnapFlowExample/`. Note any deployment-target changes clearly.

## Agent-Specific Instructions

Keep edits narrow and preserve unrelated local changes. Do not modify generated build output under `.build/`. When changing behavior, update tests or document why manual verification is sufficient.
