import AppKit
import Foundation

struct AppVersion: Comparable {
	let components: [Int]

	init(_ value: String) {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
			? String(trimmed.dropFirst())
			: trimmed

		components = normalized
			.split(separator: ".")
			.map { part in
				let numericPrefix = part.prefix { $0.isNumber }
				return Int(numericPrefix) ?? 0
			}
	}

	static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
		let count = max(lhs.components.count, rhs.components.count)
		for index in 0..<count {
			let left = index < lhs.components.count ? lhs.components[index] : 0
			let right = index < rhs.components.count ? rhs.components[index] : 0
			if left != right {
				return left < right
			}
		}
		return false
	}
}

enum AppVersionLabel {
	static func text(bundle: Bundle = .main) -> String {
		text(from: bundle.infoDictionary ?? [:])
	}

	static func text(from infoDictionary: [String: Any]) -> String {
		guard
			let version = infoDictionary["CFBundleShortVersionString"] as? String,
			!version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		else {
			return "SnapFlow 版本未知"
		}

		return "SnapFlow 版本 \(version)"
	}
}

struct GitHubReleaseAsset: Decodable {
	let name: String
	let browserDownloadURL: URL

	enum CodingKeys: String, CodingKey {
		case name
		case browserDownloadURL = "browser_download_url"
	}
}

struct GitHubRelease: Decodable {
	let tagName: String
	let name: String?
	let htmlURL: URL
	let assets: [GitHubReleaseAsset]

	enum CodingKeys: String, CodingKey {
		case tagName = "tag_name"
		case name
		case htmlURL = "html_url"
		case assets
	}
}

enum UpdateCheckResult {
	case upToDate
	case updateAvailable(release: GitHubRelease, asset: GitHubReleaseAsset)
}

enum UpdaterError: LocalizedError {
	case invalidResponse
	case missingInstallerAsset
	case downloadFailed
	case installationLaunchFailed

	var errorDescription: String? {
		switch self {
		case .invalidResponse:
			return "Unable to read the latest SnapFlow release."
		case .missingInstallerAsset:
			return "The latest release does not include a supported installer."
		case .downloadFailed:
			return "Unable to download the update."
		case .installationLaunchFailed:
			return "Unable to open the downloaded installer."
		}
	}
}

final class GitHubReleaseUpdater {
	static let releasesPageURL = URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/")!
	static let expandedAssetsBaseURL = URL(string: "https://github.com/Crazy-MT/SnapFlow/releases/expanded_assets/")!

	private let bundle: Bundle
	private let session: URLSession
	private let fileManager: FileManager
	private let workspace: NSWorkspace

	init(
		bundle: Bundle = .main,
		session: URLSession = .shared,
		fileManager: FileManager = .default,
		workspace: NSWorkspace = .shared
	) {
		self.bundle = bundle
		self.session = session
		self.fileManager = fileManager
		self.workspace = workspace
	}

	static func isRemoteVersion(_ remoteVersion: String, newerThan localVersion: String) -> Bool {
		AppVersion(remoteVersion) > AppVersion(localVersion)
	}

	static func bestInstallerAsset(from release: GitHubRelease) -> GitHubReleaseAsset? {
		release.assets.min { left, right in
			installerRank(for: left.name) < installerRank(for: right.name)
		}.flatMap { asset in
			installerRank(for: asset.name) == Int.max ? nil : asset
		}
	}

	static func latestTagName(fromReleasesPageHTML html: String) -> String? {
		let pattern = #"/Crazy-MT/SnapFlow/releases/tag/([^"]+)""#
		guard
			let regex = try? NSRegularExpression(pattern: pattern),
			let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
			let tagRange = Range(match.range(at: 1), in: html)
		else {
			return nil
		}
		return String(html[tagRange])
	}

	static func tagName(fromReleaseURL url: URL) -> String? {
		let components = url.pathComponents
		guard
			let tagIndex = components.firstIndex(of: "tag"),
			components.indices.contains(tagIndex + 1)
		else {
			return nil
		}
		return components[tagIndex + 1]
	}

	static func assets(fromExpandedAssetsHTML html: String) -> [GitHubReleaseAsset] {
		let pattern = #"href="([^"]+/releases/download/[^"]+)""#
		guard let regex = try? NSRegularExpression(pattern: pattern) else {
			return []
		}

		let range = NSRange(html.startIndex..<html.endIndex, in: html)
		return regex.matches(in: html, range: range).compactMap { match in
			guard
				let hrefRange = Range(match.range(at: 1), in: html)
			else {
				return nil
			}

			let href = html[hrefRange].replacingOccurrences(of: "&amp;", with: "&")
			let urlString = href.hasPrefix("http") ? href : "https://github.com\(href)"
			guard let url = URL(string: urlString) else {
				return nil
			}

			let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
			return GitHubReleaseAsset(name: name, browserDownloadURL: url)
		}
	}

	func checkForUpdate(completion: @escaping (Result<UpdateCheckResult, Error>) -> Void) {
		session.dataTask(with: Self.releasesPageURL) { [weak self] data, response, error in
			guard let self = self else { return }

			guard
				error == nil,
				let httpResponse = response as? HTTPURLResponse,
				(200..<300).contains(httpResponse.statusCode),
				let data = data,
				let html = String(data: data, encoding: .utf8),
				let tagName = Self.latestTagName(fromReleasesPageHTML: html)
			else {
				self.complete(.failure(UpdaterError.invalidResponse), completion: completion)
				return
			}

			self.checkForUpdateFromExpandedAssets(tagName: tagName, completion: completion)
		}.resume()
	}

	func downloadAndOpenInstaller(
		for asset: GitHubReleaseAsset,
		completion: @escaping (Result<URL, Error>) -> Void
	) {
		session.downloadTask(with: asset.browserDownloadURL) { [weak self] temporaryURL, _, error in
			guard let self = self else { return }

			if let error = error {
				self.complete(.failure(error), completion: completion)
				return
			}

			guard let temporaryURL = temporaryURL else {
				self.complete(.failure(UpdaterError.downloadFailed), completion: completion)
				return
			}

			do {
				let destinationURL = try self.downloadDestination(for: asset.name)
				if self.fileManager.fileExists(atPath: destinationURL.path) {
					try self.fileManager.removeItem(at: destinationURL)
				}
				try self.fileManager.moveItem(at: temporaryURL, to: destinationURL)
				self.openInstaller(at: destinationURL) { result in
					switch result {
					case .success:
						self.complete(.success(destinationURL), completion: completion)
					case .failure(let error):
						self.complete(.failure(error), completion: completion)
					}
				}
			} catch {
				self.complete(.failure(error), completion: completion)
			}
		}.resume()
	}

	private var currentVersion: String {
		bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
	}

	private func checkForUpdateFromExpandedAssets(
		tagName: String,
		completion: @escaping (Result<UpdateCheckResult, Error>) -> Void
	) {
		let assetsURL = Self.expandedAssetsBaseURL.appendingPathComponent(tagName)
		session.dataTask(with: assetsURL) { [weak self] data, response, error in
			guard let self = self else { return }

			guard
				error == nil,
				let httpResponse = response as? HTTPURLResponse,
				(200..<300).contains(httpResponse.statusCode),
				let data = data,
				let html = String(data: data, encoding: .utf8)
			else {
				self.complete(.failure(UpdaterError.invalidResponse), completion: completion)
				return
			}

			let release = GitHubRelease(
				tagName: tagName,
				name: nil,
				htmlURL: Self.releasesPageURL.appendingPathComponent("tag").appendingPathComponent(tagName),
				assets: Self.assets(fromExpandedAssetsHTML: html)
			)
			self.complete(self.updateCheckResult(for: release), completion: completion)
		}.resume()
	}

	private func updateCheckResult(for release: GitHubRelease) -> Result<UpdateCheckResult, Error> {
		guard Self.isRemoteVersion(release.tagName, newerThan: currentVersion) else {
			return .success(.upToDate)
		}
		guard let asset = Self.bestInstallerAsset(from: release) else {
			return .failure(UpdaterError.missingInstallerAsset)
		}
		return .success(.updateAvailable(release: release, asset: asset))
	}

	private static func installerRank(for name: String) -> Int {
		let lowercasedName = name.lowercased()
		if lowercasedName.hasSuffix(".pkg") {
			return 0
		}
		if lowercasedName.hasSuffix(".dmg") {
			return 1
		}
		if lowercasedName.hasSuffix(".zip") {
			return 2
		}
		return Int.max
	}

	private func downloadDestination(for fileName: String) throws -> URL {
		let downloadsURL = try fileManager.url(
			for: .downloadsDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)
		return downloadsURL.appendingPathComponent(fileName)
	}

	private func openInstaller(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
		switch url.pathExtension.lowercased() {
		case "pkg":
			complete(open(url), completion: completion)
		case "dmg":
			mountDiskImageAndOpenInstaller(at: url, completion: completion)
		case "zip":
			complete(open(url), completion: completion)
		default:
			complete(.failure(UpdaterError.installationLaunchFailed), completion: completion)
		}
	}

	private func mountDiskImageAndOpenInstaller(at url: URL, completion: @escaping (Result<Void, Error>) -> Void) {
		DispatchQueue.global(qos: .userInitiated).async {
			let process = Process()
			process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
			process.arguments = ["attach", "-nobrowse", "-plist", url.path]

			let pipe = Pipe()
			process.standardOutput = pipe
			process.standardError = Pipe()

			do {
				try process.run()
				process.waitUntilExit()
			} catch {
				self.complete(.failure(error), completion: completion)
				return
			}

			guard process.terminationStatus == 0 else {
				self.complete(.failure(UpdaterError.installationLaunchFailed), completion: completion)
				return
			}

			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			let mountedVolumes = self.mountedVolumes(from: data)
			guard let volumeURL = mountedVolumes.first else {
				self.complete(.failure(UpdaterError.installationLaunchFailed), completion: completion)
				return
			}

			if let packageURL = self.firstItem(in: volumeURL, withExtension: "pkg") {
				self.complete(self.open(packageURL), completion: completion)
			} else if let appURL = self.firstItem(in: volumeURL, withExtension: "app") {
				self.workspace.activateFileViewerSelecting([appURL])
				self.complete(.success(()), completion: completion)
			} else {
				self.complete(self.open(volumeURL), completion: completion)
			}
		}
	}

	private func mountedVolumes(from plistData: Data) -> [URL] {
		guard
			let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
			let dictionary = plist as? [String: Any],
			let systemEntities = dictionary["system-entities"] as? [[String: Any]]
		else {
			return []
		}

		return systemEntities.compactMap { entity in
			guard let mountPoint = entity["mount-point"] as? String else {
				return nil
			}
			return URL(fileURLWithPath: mountPoint)
		}
	}

	private func firstItem(in directoryURL: URL, withExtension pathExtension: String) -> URL? {
		guard
			let enumerator = fileManager.enumerator(
				at: directoryURL,
				includingPropertiesForKeys: [.isDirectoryKey],
				options: [.skipsHiddenFiles, .skipsPackageDescendants]
			)
		else {
			return nil
		}

		for case let itemURL as URL in enumerator where itemURL.pathExtension.lowercased() == pathExtension {
			return itemURL
		}
		return nil
	}

	private func open(_ url: URL) -> Result<Void, Error> {
		workspace.open(url) ? .success(()) : .failure(UpdaterError.installationLaunchFailed)
	}

	private func complete<Value>(
		_ result: Result<Value, Error>,
		completion: @escaping (Result<Value, Error>) -> Void
	) {
		DispatchQueue.main.async {
			completion(result)
		}
	}
}
