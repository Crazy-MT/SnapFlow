# Auto Update Design

## Goal

SnapFlow checks GitHub Releases for a newer version, downloads the newest release asset when available, and starts the macOS installation flow automatically after the download completes.

## Architecture

Add a small app-local updater service to `SnapFlowExample`. The service talks to GitHub's latest release API, compares the latest tag against `CFBundleShortVersionString`, selects the best downloadable asset, downloads it to `~/Downloads`, and opens the downloaded installer or mounted app package with standard macOS tools.

The status bar app owns user interaction. Startup checks run silently unless an update is available. A right-click menu item lets the user check manually and shows success or error alerts.

## Components

- `GitHubReleaseUpdater`: Fetches release metadata, compares versions, selects assets, downloads files, and opens installation flows.
- `AppDelegate`: Starts one background check after launch, adds a "Check for Updates..." menu item, and presents alerts.
- Tests: Cover semantic version comparison and release asset selection without network access.

## Release Source

- API endpoint: `https://api.github.com/repos/Crazy-MT/SnapFlow/releases/latest`
- Version source: release `tag_name`, with a leading `v` ignored.
- Local version source: `Bundle.main.infoDictionary["CFBundleShortVersionString"]`.

## Version Rules

Versions are compared numerically by dot-separated components. Missing components count as `0`, so `0.2.1` is newer than `0.2.0`, `0.2.1` equals `v0.2.1`, and `1.0.0` is newer than `0.2.1`.

## Asset Rules

The updater chooses one release asset in this order:

1. `.pkg`
2. `.dmg`
3. `.zip`

Other asset types are ignored. If no supported asset exists, manual checks show an alert and automatic checks stay quiet.

## Installation Flow

- `.pkg`: Open the file with the system Installer app.
- `.dmg`: Mount with `hdiutil attach`, then open the mounted volume in Finder. If the volume contains a `.pkg`, open that installer. If it contains an `.app`, reveal it in Finder so the user can replace the app.
- `.zip`: Decompress via `NSWorkspace`, then reveal the downloaded file or extracted app location.

The app does not silently overwrite a running `SnapFlow.app` and does not bypass Gatekeeper or administrator prompts.

## Error Handling

Startup checks suppress network, parsing, and asset errors unless an update was already offered to the user. Manual checks report failures in an alert. Downloads show failure alerts because the user explicitly accepted an update.

## Testing

Add unit tests for version comparison and asset selection. Network and installer launching are kept behind methods that are exercised manually through the app menu.
