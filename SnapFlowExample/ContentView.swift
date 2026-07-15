import SwiftUI
import AppKit
import SnapFlowKit

extension SnapFlowKit.Name {
	static let testShortcut1 = Self("testShortcut1")
	static let testShortcut2 = Self("testShortcut2")
	static let testShortcut3 = Self("testShortcut3")
}

final class ShortcutActionsModel: ObservableObject {
	@Published var isPressed1 = false
	@Published var isPressed2 = false
	@Published var isPressed3 = false
	@Published var path1: String {
		didSet { Self.storage.set(path1, forKey: "path1") }
	}
	@Published var path2: String {
		didSet { Self.storage.set(path2, forKey: "path2") }
	}
	@Published var path3: String {
		didSet { Self.storage.set(path3, forKey: "path3") }
	}

	private static var storage: UserDefaults {
		if #available(macOS 11.0, *) {
			return UserDefaults(suiteName: "appStorage") ?? .standard
		}
		return .standard
	}

	init() {
		path1 = Self.storage.string(forKey: "path1") ?? ""
		path2 = Self.storage.string(forKey: "path2") ?? ""
		path3 = Self.storage.string(forKey: "path3") ?? ""
		setupShortcutHandlers()
	}

	private func setupShortcutHandlers() {
		SnapFlowKit.onKeyUp(for: .testShortcut1) { [weak self] in
			self?.isPressed1 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut1) { [weak self] in
			guard let self else { return }
			isPressed1 = true
			runSoftOrScript(path: path1)
		}

		SnapFlowKit.onKeyUp(for: .testShortcut2) { [weak self] in
			self?.isPressed2 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut2) { [weak self] in
			guard let self else { return }
			isPressed2 = true
			runSoftOrScript(path: path2)
		}

		SnapFlowKit.onKeyUp(for: .testShortcut3) { [weak self] in
			self?.isPressed3 = false
		}
		SnapFlowKit.onKeyDown(for: .testShortcut3) { [weak self] in
			guard let self else { return }
			isPressed3 = true
			runSoftOrScript(path: path3)
		}
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

			TextField("未选择路径", text: $path)
				.textFieldStyle(.roundedBorder)
				.frame(maxWidth: 200)

			Button("浏览...") {
				onSelect()
			}
		}
	}
}

struct UsageGuideRow: View {
	let title: String
	let detail: String

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(title)
				.font(.subheadline)
				.fontWeight(.semibold)
			Text(detail)
				.font(.caption)
				.foregroundColor(.secondary)
				.fixedSize(horizontal: false, vertical: true)
		}
	}
}

struct ContentView: View {
	@ObservedObject var model: ShortcutActionsModel

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				GroupBox {
					VStack(alignment: .leading, spacing: 12) {
						Text("使用方法")
							.font(.headline)
							.fontWeight(.semibold)

						UsageGuideRow(
							title: "快捷键设置",
							detail: "在下方每一行点击录制框设置快捷键，再点击“浏览...”选择要打开的 App 或要运行的脚本。按下快捷键后会执行对应路径。"
						)

						UsageGuideRow(
							title: "快速搜索",
							detail: "双击 Command 打开搜索框。输入关键词直接搜索，也可以使用 pub xxx 或 github xxx 快速搜索对应站点。"
						)

						UsageGuideRow(
							title: "剪贴板历史",
							detail: "按 Command + Shift + V 打开最近复制内容，选择后回车会切回原 App 并粘贴。"
						)

						UsageGuideRow(
							title: "PasteFlow 智能动作",
							detail: "复制 URL、邮箱、颜色、JSON、算式等内容后，会自动弹出可执行动作，例如打开链接、复制格式化结果。"
						)

						UsageGuideRow(
							title: "状态栏入口",
							detail: "左键点击状态栏图标打开此设置面板，右键点击打开退出菜单。"
						)
					}
					.padding(4)
				}

				GroupBox {
					VStack(alignment: .leading, spacing: 12) {
						VStack(alignment: .leading, spacing: 6) {
							Text("快捷键设置")
								.font(.headline)
								.fontWeight(.semibold)
							Text("每组快捷键都可以绑定一个 App、.sh、.command、AppleScript 或脚本文件。")
								.foregroundColor(.secondary)
								.fixedSize(horizontal: false, vertical: true)
						}

						VStack(spacing: 12) {
							ShortcutRow(
								title: "快捷键 1",
								shortcut: .testShortcut1,
								isPressed: $model.isPressed1,
								path: $model.path1,
								onSelect: { selectSoftwareOrScript { model.path1 = $0 } }
							)
							ShortcutRow(
								title: "快捷键 2",
								shortcut: .testShortcut2,
								isPressed: $model.isPressed2,
								path: $model.path2,
								onSelect: { selectSoftwareOrScript { model.path2 = $0 } }
							)
							ShortcutRow(
								title: "快捷键 3",
								shortcut: .testShortcut3,
								isPressed: $model.isPressed3,
								path: $model.path3,
								onSelect: { selectSoftwareOrScript { model.path3 = $0 } }
							)
						}
					}
					.padding(4)
				}

				Text(AppVersionLabel.text())
					.font(.caption)
					.foregroundColor(.secondary)
					.frame(maxWidth: .infinity, alignment: .center)
			}
			.padding()
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(width: 560, height: 420)
	}
}

private func selectSoftwareOrScript(onSelect: @escaping (String) -> Void) {
	let openPanel = NSOpenPanel()
	openPanel.allowedFileTypes = ["app", "sh", "command", "scpt", "applescript"]
	openPanel.allowsMultipleSelection = false
	openPanel.canChooseDirectories = false
	openPanel.canChooseFiles = true
	openPanel.message = "选择一个 App 或脚本"

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
