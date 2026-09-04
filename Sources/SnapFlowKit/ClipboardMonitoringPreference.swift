import Foundation

public struct ClipboardMonitoringPreference {
	private static let key = "isClipboardMonitoringEnabled"
	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	public var isEnabled: Bool {
		get {
			(defaults.object(forKey: Self.key) as? Bool) ?? true
		}
		set {
			defaults.set(newValue, forKey: Self.key)
		}
	}
}

public struct NetworkSpeedPreference {
	private static let key = "isNetworkSpeedEnabled"
	private let defaults: UserDefaults

	public init(defaults: UserDefaults = .standard) {
		self.defaults = defaults
	}

	public var isEnabled: Bool {
		get {
			(defaults.object(forKey: Self.key) as? Bool) ?? true
		}
		set {
			defaults.set(newValue, forKey: Self.key)
		}
	}
}
