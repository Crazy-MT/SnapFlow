import Foundation

struct ApplicationSearchResult: Equatable {
	let name: String
	let url: URL
	let aliases: [String]

	init(name: String, url: URL, aliases: [String] = []) {
		self.name = name
		self.url = url
		self.aliases = aliases
	}

	static func filtered(_ applications: [Self], query: String, limit: Int = 6) -> [Self] {
		let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedQuery.isEmpty else { return [] }

		return applications
			.filter { $0.matches(trimmedQuery) }
			.sorted { left, right in
				let leftRank = left.rank(for: trimmedQuery)
				let rightRank = right.rank(for: trimmedQuery)
				if leftRank != rightRank {
					return leftRank < rightRank
				}
				return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
			}
			.prefix(limit)
			.map { $0 }
	}

	static func installedApplications(
		fileManager: FileManager = .default,
		homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
	) -> [Self] {
		let directories = [
			URL(fileURLWithPath: "/Applications", isDirectory: true),
			URL(fileURLWithPath: "/System/Applications", isDirectory: true),
			homeDirectory.appendingPathComponent("Applications", isDirectory: true)
		]

		var applications = [Self]()
		var seenURLs = Set<URL>()
		for directory in directories where fileManager.fileExists(atPath: directory.path) {
			guard let enumerator = fileManager.enumerator(
				at: directory,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles]
			) else {
				continue
			}

			for case let url as URL in enumerator where url.pathExtension == "app" {
				if seenURLs.insert(url).inserted {
					let displayName = fileManager.displayName(atPath: url.path).appNameWithoutExtension
					applications.append(Self(
						name: displayName,
						url: url,
						aliases: localizedNames(for: url) + [url.deletingPathExtension().lastPathComponent]
					))
				}
				enumerator.skipDescendants()
			}
		}

		return applications.sorted {
			$0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
		}
	}

	private func matches(_ query: String) -> Bool {
		searchableNames.contains { $0.contains(query.normalizedForApplicationSearch) }
	}

	private func rank(for query: String) -> Int {
		let normalizedQuery = query.normalizedForApplicationSearch
		if searchableNames.contains(normalizedQuery) {
			return 0
		}
		if searchableNames.contains(where: { $0.hasPrefix(normalizedQuery) }) {
			return 1
		}
		return 2
	}

	private var searchableNames: [String] {
		([name] + aliases).map(\.normalizedForApplicationSearch)
	}

	private static func localizedNames(for appURL: URL) -> [String] {
		let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
		let loctableURL = resourcesURL.appendingPathComponent("InfoPlist.loctable")
		var names = Set<String>()

		if let table = NSDictionary(contentsOf: loctableURL) {
			for case let localization as NSDictionary in table.allValues {
				for key in ["CFBundleDisplayName", "CFBundleName"] {
					if let name = (localization[key] as? String)?.appNameWithoutExtension, !name.isEmpty {
						names.insert(name)
					}
				}
			}
		}

		if let resourceDirectories = try? FileManager.default.contentsOfDirectory(
			at: resourcesURL,
			includingPropertiesForKeys: nil
		) {
			for directory in resourceDirectories where directory.pathExtension == "lproj" {
				let stringsURL = directory.appendingPathComponent("InfoPlist.strings")
				guard let strings = NSDictionary(contentsOf: stringsURL) else { continue }
				for key in ["CFBundleDisplayName", "CFBundleName"] {
					if let name = (strings[key] as? String)?.appNameWithoutExtension, !name.isEmpty {
						names.insert(name)
					}
				}
			}
		}

		return names.sorted {
			$0.localizedCaseInsensitiveCompare($1) == .orderedAscending
		}
	}
}

private extension String {
	var normalizedForApplicationSearch: String {
		folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
	}

	var appNameWithoutExtension: String {
		hasSuffix(".app") ? String(dropLast(4)) : self
	}
}

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
