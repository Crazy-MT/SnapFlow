import Cocoa
import ApplicationServices
import CoreGraphics
import SwiftUI

enum SnapFlowPermissionGuide {
	static var hasAccessibilityAccess: Bool {
		AXIsProcessTrusted()
	}

	static var hasScreenCaptureAccess: Bool {
		if #available(macOS 10.15, *) {
			return CGPreflightScreenCaptureAccess()
		}
		return true
	}

	static var needsGuide: Bool {
		!hasAccessibilityAccess || !hasScreenCaptureAccess
	}

	static func requestAccessibilityAccess() {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
		openAccessibilitySettings()
	}

	static func requestScreenCaptureAccess() {
		if #available(macOS 10.15, *), !CGPreflightScreenCaptureAccess() {
			CGRequestScreenCaptureAccess()
		}
		openScreenCaptureSettings()
	}

	static func openAccessibilitySettings() {
		openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
	}

	static func openScreenCaptureSettings() {
		openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
	}

	private static func openSettings(_ rawValue: String) {
		guard let url = URL(string: rawValue) else { return }
		NSWorkspace.shared.open(url)
	}
}

final class PermissionGuideModel: ObservableObject {
	@Published private var refreshToken = UUID()

	var hasAccessibilityAccess: Bool {
		_ = refreshToken
		return SnapFlowPermissionGuide.hasAccessibilityAccess
	}

	var hasScreenCaptureAccess: Bool {
		_ = refreshToken
		return SnapFlowPermissionGuide.hasScreenCaptureAccess
	}

	func refresh() {
		refreshToken = UUID()
	}
}

final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {
	private let onClose: () -> Void
	private let model = PermissionGuideModel()

	init(onClose: @escaping () -> Void) {
		self.onClose = onClose

		let window = KeyableWindow(
			contentRect: CGRect(x: 0, y: 0, width: 520, height: 420),
			styleMask: [.titled, .closable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.title = "SnapFlow 权限引导"
		window.center()
		window.isReleasedWhenClosed = false

		super.init(window: window)

		window.delegate = self
		window.contentViewController = NSHostingController(rootView: PermissionGuideView(model: model))

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(refresh),
			name: NSApplication.didBecomeActiveNotification,
			object: nil
		)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	func show() {
		model.refresh()
		window?.center()
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func windowWillClose(_ notification: Notification) {
		onClose()
	}

	@objc
	private func refresh() {
		model.refresh()
	}
}

private struct PermissionGuideView: View {
	@ObservedObject var model: PermissionGuideModel

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 6) {
				Text("先把权限开好")
					.font(.title)
					.fontWeight(.semibold)
				Text("SnapFlow 只在需要的功能上申请权限。完成每一步后回到这里，状态会自动刷新。")
					.foregroundColor(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			PermissionStepView(
				number: "1",
				title: "辅助功能",
				detail: "用于全局快捷键、双击 Command 搜索、切回原 App 后自动粘贴和窗口聚焦。",
				isGranted: model.hasAccessibilityAccess,
				buttonTitle: "打开辅助功能设置"
			) {
				SnapFlowPermissionGuide.requestAccessibilityAccess()
				model.refresh()
			}

			PermissionStepView(
				number: "2",
				title: "屏幕录制",
				detail: "用于窗口切换时读取窗口列表和缩略图；不开也不会影响普通快捷键。",
				isGranted: model.hasScreenCaptureAccess,
				buttonTitle: "打开屏幕录制设置"
			) {
				SnapFlowPermissionGuide.requestScreenCaptureAccess()
				model.refresh()
			}

			Spacer()

			HStack {
				Text(model.hasAccessibilityAccess && model.hasScreenCaptureAccess ? "权限已完成" : "设置完成后可能需要重启 SnapFlow")
					.font(.caption)
					.foregroundColor(.secondary)
				Spacer()
				Button("刷新") {
					model.refresh()
				}
			}
		}
		.padding(24)
		.frame(width: 520, height: 420)
	}
}

private struct PermissionStepView: View {
	let number: String
	let title: String
	let detail: String
	let isGranted: Bool
	let buttonTitle: String
	let action: () -> Void

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Text(number)
				.font(.headline)
				.foregroundColor(.white)
				.frame(width: 28, height: 28)
				.background(Circle().fill(isGranted ? Color.green : Color.accentColor))

			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text(title)
						.font(.headline)
					Text(isGranted ? "已开启" : "未开启")
						.font(.caption)
						.foregroundColor(isGranted ? .green : .secondary)
				}

				Text(detail)
					.font(.subheadline)
					.foregroundColor(.secondary)
					.fixedSize(horizontal: false, vertical: true)

				if !isGranted {
					Button(buttonTitle, action: action)
				}
			}
		}
	}
}
