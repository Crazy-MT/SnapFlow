import XCTest

final class GitHubReleaseUpdaterTests: XCTestCase {
	func testAppVersionLabelUsesShortVersion() {
		let label = AppVersionLabel.text(from: [
			"CFBundleShortVersionString": "0.2.1",
			"CFBundleVersion": "7"
		])

		XCTAssertEqual(label, "SnapFlow 版本 0.2.1")
	}

	func testAppVersionLabelFallsBackWhenVersionIsUnavailable() {
		let label = AppVersionLabel.text(from: [:])

		XCTAssertEqual(label, "SnapFlow 版本未知")
	}

	func testRemoteVersionComparisonIgnoresLeadingVAndUsesNumericComponents() {
		XCTAssertTrue(GitHubReleaseUpdater.isRemoteVersion("v0.2.1", newerThan: "0.2.0"))
		XCTAssertFalse(GitHubReleaseUpdater.isRemoteVersion("v0.2.1", newerThan: "0.2.1"))
		XCTAssertFalse(GitHubReleaseUpdater.isRemoteVersion("v0.2.1", newerThan: "1.0.0"))
		XCTAssertFalse(GitHubReleaseUpdater.isRemoteVersion("v0.2.0", newerThan: "0.2"))
		XCTAssertTrue(GitHubReleaseUpdater.isRemoteVersion("v0.2.1", newerThan: "0.2"))
	}

	func testBestInstallerAssetPrefersPkgThenDmgThenZip() {
		let release = GitHubRelease(
			tagName: "v0.2.1",
			name: "SnapFlow v0.2.1",
			htmlURL: URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/tag/v0.2.1")!,
			assets: [
				asset(named: "SnapFlow.zip"),
				asset(named: "SnapFlow.dmg"),
				asset(named: "SnapFlow.pkg")
			]
		)

		XCTAssertEqual(GitHubReleaseUpdater.bestInstallerAsset(from: release)?.name, "SnapFlow.pkg")
	}

	func testBestInstallerAssetFallsBackToDmgThenZip() {
		let dmgRelease = GitHubRelease(
			tagName: "v0.2.1",
			name: "SnapFlow v0.2.1",
			htmlURL: URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/tag/v0.2.1")!,
			assets: [
				asset(named: "notes.txt"),
				asset(named: "SnapFlow.zip"),
				asset(named: "SnapFlow.dmg")
			]
		)
		let zipRelease = GitHubRelease(
			tagName: "v0.2.1",
			name: "SnapFlow v0.2.1",
			htmlURL: URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/tag/v0.2.1")!,
			assets: [
				asset(named: "notes.txt"),
				asset(named: "SnapFlow.zip")
			]
		)

		XCTAssertEqual(GitHubReleaseUpdater.bestInstallerAsset(from: dmgRelease)?.name, "SnapFlow.dmg")
		XCTAssertEqual(GitHubReleaseUpdater.bestInstallerAsset(from: zipRelease)?.name, "SnapFlow.zip")
	}

	func testBestInstallerAssetIgnoresUnsupportedAssets() {
		let release = GitHubRelease(
			tagName: "v0.2.1",
			name: "SnapFlow v0.2.1",
			htmlURL: URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/tag/v0.2.1")!,
			assets: [
				asset(named: "source.tar.gz"),
				asset(named: "checksum.txt")
			]
		)

		XCTAssertNil(GitHubReleaseUpdater.bestInstallerAsset(from: release))
	}

	func testLatestTagNameCanBeReadFromReleasesPageHTML() {
		let html = """
		<a href="/Crazy-MT/SnapFlow/releases/tag/v0.2.1">SnapFlow v0.2.1</a>
		<include-fragment src="https://github.com/Crazy-MT/SnapFlow/releases/expanded_assets/v0.2.1"></include-fragment>
		<a href="/Crazy-MT/SnapFlow/releases/tag/v0.2.0">SnapFlow v0.2.0</a>
		"""

		XCTAssertEqual(GitHubReleaseUpdater.latestTagName(fromReleasesPageHTML: html), "v0.2.1")
	}

	func testExpandedAssetsHTMLParsesReleaseDownloadLinksOnly() {
		let html = """
		<a href="/Crazy-MT/SnapFlow/releases/download/v0.2.1/SnapFlow-v0.2.1.zip">SnapFlow-v0.2.1.zip</a>
		<a href="/Crazy-MT/SnapFlow/archive/refs/tags/v0.2.1.zip">Source code</a>
		<a href="/Crazy-MT/SnapFlow/releases/download/v0.2.1/SnapFlow-v0.2.1.dmg">SnapFlow-v0.2.1.dmg</a>
		"""

		let assets = GitHubReleaseUpdater.assets(fromExpandedAssetsHTML: html)

		XCTAssertEqual(assets.map(\.name), ["SnapFlow-v0.2.1.zip", "SnapFlow-v0.2.1.dmg"])
		XCTAssertEqual(
			assets.first?.browserDownloadURL.absoluteString,
			"https://github.com/Crazy-MT/SnapFlow/releases/download/v0.2.1/SnapFlow-v0.2.1.zip"
		)
	}

	private func asset(named name: String) -> GitHubReleaseAsset {
		GitHubReleaseAsset(
			name: name,
			browserDownloadURL: URL(string: "https://example.com/\(name)")!
		)
	}
}
