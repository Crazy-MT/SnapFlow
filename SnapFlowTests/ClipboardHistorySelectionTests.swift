import XCTest

final class ClipboardHistorySelectionTests: XCTestCase {
	func testSelectsNextItemHorizontallyWithWrapping() {
		XCTAssertEqual(ClipboardHistorySelection.nextIndex(current: 0, count: 3), 1)
		XCTAssertEqual(ClipboardHistorySelection.nextIndex(current: 2, count: 3), 0)
	}

	func testSelectsPreviousItemHorizontallyWithWrapping() {
		XCTAssertEqual(ClipboardHistorySelection.previousIndex(current: 0, count: 3), 2)
		XCTAssertEqual(ClipboardHistorySelection.previousIndex(current: 2, count: 3), 1)
	}

	func testReplacingSelectionKeepsOnlyOneSelectedItem() {
		XCTAssertEqual(
			ClipboardHistorySelection.replacingSelection(with: 2, count: 4),
			[2]
		)
	}

	func testDisplayTextPreservesNewlines() {
		XCTAssertEqual(
			ClipboardHistorySelection.displayText(for: "第一行\n第二行"),
			"第一行\n第二行"
		)
	}

	func testSourceTextUsesAppName() {
		XCTAssertEqual(
			ClipboardHistorySelection.sourceText(for: "Safari"),
			"来自 Safari"
		)
	}

	func testSourceTextFallsBackForEmptyAppName() {
		XCTAssertEqual(
			ClipboardHistorySelection.sourceText(for: "   "),
			"来自 未知应用"
		)
	}

	func testInsertingDuplicateContentKeepsLatestSource() {
		let items = [
			ClipboardHistoryItem(content: "hello", sourceAppName: "Safari")
		]

		XCTAssertEqual(
			ClipboardHistorySelection.inserting(
				ClipboardHistoryItem(content: "hello", sourceAppName: "Notes"),
				into: items,
				maxItems: 10
			),
			[
				ClipboardHistoryItem(content: "hello", sourceAppName: "Notes")
			]
		)
	}

	func testPreviewTitleDescribesImageItem() {
		XCTAssertEqual(
			ClipboardHistorySelection.previewTitle(
				for: ClipboardHistoryItem(
					content: .image(Data([1, 2, 3])),
					source: ClipboardHistorySource(appName: "Preview")
				)
			),
			"图片"
		)
	}

	func testPreviewTitleDescribesFileItems() {
		XCTAssertEqual(
			ClipboardHistorySelection.previewTitle(
				for: ClipboardHistoryItem(
					content: .files([
						URL(fileURLWithPath: "/tmp/a.txt"),
						URL(fileURLWithPath: "/tmp/b.txt")
					]),
					source: ClipboardHistorySource(appName: "Finder")
				)
			),
			"2 个文件"
		)
	}

	func testContentIdentityKeepsDifferentTypesSeparate() {
		let items = [
			ClipboardHistoryItem(
				content: .text("hello"),
				source: ClipboardHistorySource(appName: "Safari")
			)
		]

		XCTAssertEqual(
			ClipboardHistorySelection.inserting(
				ClipboardHistoryItem(
					content: .image(Data("hello".utf8)),
					source: ClipboardHistorySource(appName: "Preview")
				),
				into: items,
				maxItems: 10
			).count,
			2
		)
	}
}
