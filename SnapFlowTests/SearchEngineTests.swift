import XCTest

final class SearchEngineTests: XCTestCase {
	func testBuildsBingSearchURL() {
		XCTAssertEqual(
			SearchEngine.bing.searchURL(for: "swift keyboard")?.absoluteString,
			"https://www.bing.com/search?q=swift%20keyboard"
		)
	}

	func testBuildsGoogleSearchURL() {
		XCTAssertEqual(
			SearchEngine.google.searchURL(for: "swift keyboard")?.absoluteString,
			"https://www.google.com/search?q=swift%20keyboard"
		)
	}

	func testApplicationSearchPrefersPrefixMatch() {
		let results = ApplicationSearchResult.filtered(
			[
				ApplicationSearchResult(name: "Visual Studio Code", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app")),
				ApplicationSearchResult(name: "Calendar", url: URL(fileURLWithPath: "/System/Applications/Calendar.app")),
				ApplicationSearchResult(name: "CodeRunner", url: URL(fileURLWithPath: "/Applications/CodeRunner.app"))
			],
			query: "code"
		)

		XCTAssertEqual(results.map(\.name), ["CodeRunner", "Visual Studio Code"])
	}

	func testApplicationSearchMatchesChineseDisplayName() {
		let results = ApplicationSearchResult.filtered(
			[
				ApplicationSearchResult(
					name: "备忘录",
					url: URL(fileURLWithPath: "/System/Applications/Notes.app"),
					aliases: ["Notes"]
				),
				ApplicationSearchResult(name: "Calendar", url: URL(fileURLWithPath: "/System/Applications/Calendar.app"))
			],
			query: "备忘"
		)

		XCTAssertEqual(results.map(\.name), ["备忘录"])
	}
}
