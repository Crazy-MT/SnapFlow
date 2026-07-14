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
}
