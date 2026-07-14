import XCTest
@testable import SnapFlowKit

final class SnapFlowTests: XCTestCase {
	// TODO: Add more tests.

	override func setUpWithError() throws {
		UserDefaults.standard.removeAll()
	}

	func testSetShortcutAndReset() throws {
		let defaultShortcut = SnapFlowKit.Shortcut(.c)
		let shortcut1 = SnapFlowKit.Shortcut(.a)
		let shortcut2 = SnapFlowKit.Shortcut(.b)

		let shortcutName1 = SnapFlowKit.Name("testSetShortcutAndReset1")
		let shortcutName2 = SnapFlowKit.Name("testSetShortcutAndReset2", default: defaultShortcut)

		SnapFlowKit.setShortcut(shortcut1, for: shortcutName1)
		SnapFlowKit.setShortcut(shortcut2, for: shortcutName2)

		XCTAssertEqual(SnapFlowKit.getShortcut(for: shortcutName1), shortcut1)
		XCTAssertEqual(SnapFlowKit.getShortcut(for: shortcutName2), shortcut2)

		SnapFlowKit.reset(shortcutName1, shortcutName2)

		XCTAssertNil(SnapFlowKit.getShortcut(for: shortcutName1))
		XCTAssertEqual(SnapFlowKit.getShortcut(for: shortcutName2), defaultShortcut)
	}

	func testKeyDownOnlyTriggersOnceUntilKeyUp() {
		let shortcut = SnapFlowKit.Shortcut(.a, modifiers: [.command])
		let shortcutName = SnapFlowKit.Name("testKeyDownOnlyTriggersOnceUntilKeyUp")
		var triggerCount = 0

		SnapFlowKit.setShortcut(shortcut, for: shortcutName)
		SnapFlowKit.onKeyDown(for: shortcutName) {
			triggerCount += 1
		}

		SnapFlowKit.simulateKeyDown(for: shortcut)
		SnapFlowKit.simulateKeyDown(for: shortcut)

		XCTAssertEqual(triggerCount, 1)

		SnapFlowKit.simulateKeyUp(for: shortcut)
		SnapFlowKit.simulateKeyDown(for: shortcut)

		XCTAssertEqual(triggerCount, 2)
	}
}
