import Foundation

enum SearchEngine: String, CaseIterable {
	case bing
	case google

	private static let storageKey = "searchEngine"

	static var saved: Self {
		get {
			guard
				let rawValue = UserDefaults.standard.string(forKey: storageKey),
				let searchEngine = Self(rawValue: rawValue)
			else {
				return .bing
			}

			return searchEngine
		}
		set {
			UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
		}
	}

	var title: String {
		switch self {
		case .bing:
			return "Bing"
		case .google:
			return "Google"
		}
	}

	func searchURL(for query: String) -> URL? {
		var components = URLComponents()
		components.scheme = "https"
		components.host = host
		components.path = "/search"
		components.queryItems = [
			URLQueryItem(name: "q", value: query)
		]
		return components.url
	}

	private var host: String {
		switch self {
		case .bing:
			return "www.bing.com"
		case .google:
			return "www.google.com"
		}
	}
}
