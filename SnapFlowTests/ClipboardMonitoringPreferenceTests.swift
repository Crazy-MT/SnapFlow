import XCTest
@testable import SnapFlowKit

final class ClipboardMonitoringPreferenceTests: XCTestCase {
	private var defaults: UserDefaults!

	override func setUpWithError() throws {
		defaults = UserDefaults(suiteName: "ClipboardMonitoringPreferenceTests")!
		defaults.removeAll()
	}

	func testDefaultsToEnabled() {
		XCTAssertTrue(ClipboardMonitoringPreference(defaults: defaults).isEnabled)
	}

	func testPersistsDisabledState() {
		var preference = ClipboardMonitoringPreference(defaults: defaults)

		preference.isEnabled = false

		XCTAssertFalse(ClipboardMonitoringPreference(defaults: defaults).isEnabled)
	}

	func testNetworkSpeedDefaultsToEnabled() {
		XCTAssertTrue(NetworkSpeedPreference(defaults: defaults).isEnabled)
	}

	func testNetworkSpeedPersistsDisabledState() {
		var preference = NetworkSpeedPreference(defaults: defaults)

		preference.isEnabled = false

		XCTAssertFalse(NetworkSpeedPreference(defaults: defaults).isEnabled)
	}
}
