import SwiftUI
import AppKit
import SnapFlowKit

extension SnapFlowKit.Name {
	static let testShortcut1 = Self("testShortcut1")
	static let testShortcut2 = Self("testShortcut2")
	static let testShortcut3 = Self("testShortcut3")
}

@propertyWrapper
struct BackwardsCompatibleAppStorage: DynamicProperty {
	@State private var value: String
	private let key: String

	init(wrappedValue defaultValue: String, _ key: String) {
		self.key = key
		if #available(macOS 11.0, *) {
			let storage = UserDefaults(suiteName: "appStorage") ?? .standard
			_value = State(initialValue: storage.string(forKey: key) ?? defaultValue)
		} else {
			_value = State(initialValue: UserDefaults.standard.string(forKey: key) ?? defaultValue)
		}
	}

	var wrappedValue: String {
		get { value }
		nonmutating set {
			value = newValue
			if #available(macOS 11.0, *) {
				let storage = UserDefaults(suiteName: "appStorage") ?? .standard
				storage.set(newValue, forKey: key)
			} else {
				UserDefaults.standard.set(newValue, forKey: key)
			}
		}
	}

	var projectedValue: Binding<String> {
		Binding(
			get: { wrappedValue },
			set: { wrappedValue = $0 }
		)
	}
}

struct ShortcutRow: View {
	let title: String
	let shortcut: SnapFlowKit.Name
	@Binding var isPressed: Bool
	@Binding var path: String
	let onSelect: () -> Void

	var body: some View {
		HStack {
			Text(title)
				.frame(width: 80, alignment: .leading)

			SnapFlowKit.Recorder(for: shortcut)

			TextField("No path selected", text: $path)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: 200)

			Button("Browse...") {
				onSelect()
			}
		}
	}
}

struct ContentView: View {
	@State private var isPressed1 = false
	@State private var isPressed2 = false
	@State private var isPressed3 = false
	@BackwardsCompatibleAppStorage("path1") private var path1 = ""
	@BackwardsCompatibleAppStorage("path2") private var path2 = ""
	@BackwardsCompatibleAppStorage("path3") private var path3 = ""

	@State private var didSetupHandlers = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 6) {
					Text("Keyboard Shortcuts")
						.font(.headline)
						.fontWeight(.semibold)
					Text("Assign a shortcut and choose an app or a .sh script to run.")
						.foregroundColor(.secondary)
				}

				GroupBox {
					VStack(spacing: 12) {
						ShortcutRow(
							title: "Shortcut 1",
							shortcut: .testShortcut1,
							isPressed: $isPressed1,
							path: $path1,
							onSelect: { selectSoftwareOrScript { path1 = $0 } }
						)
						ShortcutRow(
							title: "Shortcut 2",
							shortcut: .testShortcut2,
							isPressed: $isPressed2,
							path: $path2,
							onSelect: { selectSoftwareOrScript { path2 = $0 } }
						)
						ShortcutRow(
							title: "Shortcut 3",
							shortcut: .testShortcut3,
							isPressed: $isPressed3,
							path: $path3,
							onSelect: { selectSoftwareOrScript { path3 = $0 } }
						)
					}
					.padding(4)
				}
				GroupBox {
					ForEach(0..<3) { index in
						HStack {
							Text("Status \(index + 1):")
							Spacer()
							Text(statusText(for: index))
								.foregroundColor(.secondary)
						}
					}
				}
			}
			.padding()
		}
		.frame(minWidth: 500, minHeight: 400)
		.onAppear { setup() }
	}

	private func statusText(for index: Int) -> String {
		switch index {
		case 0: return isPressed1 ? "Pressed" : "Idle"
		case 1: return isPressed2 ? "Pressed" : "Idle"
		case 2: return isPressed3 ? "Pressed" : "Idle"
		default: return "Unknown"
		}
	}

	private func setup() {
		guard !didSetupHandlers else { return }
		didSetupHandlers = true

		SnapFlowKit.onKeyUp(for: .testShortcut1) { [self] in
			isPressed1 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut1) { [self] in
			isPressed1 = true
			runSoftOrScript(path: path1)
		}

		SnapFlowKit.onKeyUp(for: .testShortcut2) { [self] in
			isPressed2 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut2) { [self] in
			isPressed2 = true
			runSoftOrScript(path: path2)
		}

		SnapFlowKit.onKeyUp(for: .testShortcut3) { [self] in
			isPressed3 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut3) { [self] in
			isPressed3 = true
			runSoftOrScript(path: path3)
		}
	}
}

private func selectSoftwareOrScript(onSelect: @escaping (String) -> Void) {
	let openPanel = NSOpenPanel()
	openPanel.allowedFileTypes = ["app", "sh", "command", "scpt", "applescript"]
	openPanel.allowsMultipleSelection = false
	openPanel.canChooseDirectories = false
	openPanel.canChooseFiles = true
	openPanel.message = "Select an app or script"

	if openPanel.runModal() == .OK {
		onSelect(openPanel.url?.path ?? "")
	}
}

private func runSoftOrScript(path: String) {
	let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
	guard !trimmedPath.isEmpty else { return }

	let url = URL(fileURLWithPath: trimmedPath)

	if url.pathExtension.lowercased() == "app" {
		if #available(macOS 10.15, *) {
			_ = try? NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
		} else {
			NSWorkspace.shared.openFile(url.path)
		}
		return
	}

	let task = Process()
	do {
		if FileManager.default.isExecutableFile(atPath: url.path) {
			task.executableURL = url
			task.arguments = []
		} else {
			task.executableURL = URL(fileURLWithPath: "/bin/zsh")
			task.arguments = [url.path]
		}

		try task.run()
	} catch {
		NSSound.beep()
	}
}
