import Foundation

struct ClipboardHistorySource: Equatable {
	let appName: String?
	let bundleIdentifier: String?
	let bundleURL: URL?

	init(appName: String?, bundleIdentifier: String? = nil, bundleURL: URL? = nil) {
		self.appName = appName
		self.bundleIdentifier = bundleIdentifier
		self.bundleURL = bundleURL
	}
}

enum ClipboardHistoryContent: Equatable {
	case text(String)
	case image(Data)
	case files([URL])
}

struct ClipboardHistoryItem: Equatable {
	let content: ClipboardHistoryContent
	let source: ClipboardHistorySource

	init(content: ClipboardHistoryContent, source: ClipboardHistorySource) {
		self.content = content
		self.source = source
	}

	init(content: String, sourceAppName: String?) {
		self.content = .text(content)
		self.source = ClipboardHistorySource(appName: sourceAppName)
	}

	var sourceAppName: String? {
		source.appName
	}
}

enum ClipboardHistorySelection {
	static func nextIndex(current: Int, count: Int) -> Int {
		guard count > 0 else { return -1 }
		return (max(current, 0) + 1) % count
	}

	static func previousIndex(current: Int, count: Int) -> Int {
		guard count > 0 else { return -1 }
		return (max(current, 0) - 1 + count) % count
	}

	static func replacingSelection(with index: Int, count: Int) -> Set<Int> {
		guard index >= 0, index < count else { return [] }
		return [index]
	}

	static func displayText(for text: String) -> String {
		text
	}

	static func previewTitle(for item: ClipboardHistoryItem) -> String {
		switch item.content {
		case let .text(text):
			return text
		case .image:
			return "图片"
		case let .files(urls):
			if urls.count == 1 {
				return urls[0].lastPathComponent
			}

			return "\(urls.count) 个文件"
		}
	}

	static func sourceText(for sourceAppName: String?) -> String {
		let appName = sourceAppName?.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let appName, !appName.isEmpty else {
			return "来自 未知应用"
		}

		return "来自 \(appName)"
	}

	static func inserting(
		_ item: ClipboardHistoryItem,
		into items: [ClipboardHistoryItem],
		maxItems: Int
	) -> [ClipboardHistoryItem] {
		var updatedItems = items.filter { $0.content != item.content }
		updatedItems.insert(item, at: 0)
		if updatedItems.count > maxItems {
			updatedItems.removeLast(updatedItems.count - maxItems)
		}

		return updatedItems
	}
}
