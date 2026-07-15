import Cocoa

/// PasteFlow 浮动动作面板：在光标附近弹出，展示检测到的内容与主操作。
/// 回车执行、Esc 关闭、失焦自动消失。仿 `SearchWindowController` 实现。
final class PasteFlowWindowController: NSWindowController, NSWindowDelegate {
	private let type: PasteFlowType
	private let onClose: () -> Void
	private var keyDownMonitor: Any?
	private var isClosing = false
	private var actions: [PasteFlowActionButton] = []

	var isVisible: Bool {
		guard let window else { return false }
		return window.isVisible && !isClosing
	}

	init(type: PasteFlowType, onClose: @escaping () -> Void) {
		self.type = type
		self.onClose = onClose

		// JSON 内容多行，需要更大的窗口容纳格式化结果。
		let isJSON: Bool
		if case .json = type { isJSON = true } else { isJSON = false }
		let contentSize = isJSON ? CGSize(width: 520, height: 320) : CGSize(width: 420, height: 96)

		let window = PasteFlowPanel(
			contentRect: CGRect(origin: .zero, size: contentSize),
			styleMask: [.borderless, .nonactivatingPanel],
			backing: .buffered,
			defer: false
		)
		window.title = "PasteFlow"
		window.isMovableByWindowBackground = true
		window.level = .floating
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = true
		window.hidesOnDeactivate = false // App 失活时不自动隐藏
		window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

		super.init(window: window)

		window.delegate = self
		self.actions = Self.actionButtons(for: type)
		setupContentView()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// MARK: - Show / Close

	func show() {
		isClosing = false
		positionNearCursor()
		window?.alphaValue = 0
		// 用非激活方式显示：orderFrontRegardless + makeKey 让面板浮现并能接收
		// 回车/Esc，但不调用 NSApp.activate —— 否则会把整个 App（含主窗口）拽到前台。
		window?.orderFrontRegardless()
		window?.makeKey()
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			self.window?.animator().alphaValue = 1
		}
	}

	func closeWindow() {
		guard !isClosing else { return }
		isClosing = true

		guard let window else { return }
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			window.animator().alphaValue = 0
		} completionHandler: {
			window.close()
		}
	}

	private func positionNearCursor() {
		guard let window else { return }
		let mouse = NSEvent.mouseLocation
		let size = window.frame.size
		var origin = CGPoint(x: mouse.x + 12, y: mouse.y - size.height - 12)

		// 钳制到鼠标所在屏幕的可见区域内。
		let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
		if let visible = screen?.visibleFrame {
			origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
			origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
		}
		window.setFrameOrigin(origin)
	}

	// MARK: - Actions

	@objc private func runPrimaryAction() {
		actions.first?.handler()
		closeWindow()
	}

	@objc private func actionButtonTapped(_ sender: NSButton) {
		guard sender.tag >= 0, sender.tag < actions.count else { return }
		actions[sender.tag].handler()
		closeWindow()
	}

	// MARK: - Content

	private func setupContentView() {
		guard let window else { return }

		let rootView = NSView()

		let backgroundView = NSVisualEffectView()
		backgroundView.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.state = .active
		backgroundView.blendingMode = .behindWindow
		backgroundView.material = .hudWindow
		backgroundView.wantsLayer = true
		backgroundView.layer?.cornerRadius = 16
		backgroundView.layer?.borderWidth = 1
		backgroundView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
		backgroundView.layer?.masksToBounds = true
		rootView.addSubview(backgroundView)

		let contentView = NSView()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(contentView)

		let topRow = NSStackView()
		topRow.translatesAutoresizingMaskIntoConstraints = false
		topRow.orientation = .horizontal
		topRow.alignment = .centerY
		topRow.spacing = 10
		contentView.addSubview(topRow)

		if #available(macOS 11.0, *) {
			let iconView = NSImageView()
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
			iconView.image = NSImage(systemSymbolName: Self.iconName(for: type), accessibilityDescription: nil)
			iconView.contentTintColor = .controlAccentColor
			topRow.addArrangedSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.widthAnchor.constraint(equalToConstant: 22),
				iconView.heightAnchor.constraint(equalToConstant: 22)
			])
		}

		// 颜色类型：展示一个填充该颜色的色块，便于直观预览。
		if case let .color(color) = type {
			let swatch = NSView()
			swatch.translatesAutoresizingMaskIntoConstraints = false
			swatch.wantsLayer = true
			swatch.layer?.backgroundColor = NSColor(
				red: CGFloat(color.red) / 255,
				green: CGFloat(color.green) / 255,
				blue: CGFloat(color.blue) / 255,
				alpha: 1
			).cgColor
			swatch.layer?.cornerRadius = 5
			swatch.layer?.borderWidth = 1
			swatch.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
			topRow.addArrangedSubview(swatch)
			NSLayoutConstraint.activate([
				swatch.widthAnchor.constraint(equalToConstant: 24),
				swatch.heightAnchor.constraint(equalToConstant: 24)
			])
		}

		var jsonScrollView: NSScrollView?
		if case let .json(pretty) = type {
			// JSON：等宽多行文本 + 滚动视图，展示格式化结果。
			let textView = NSTextView()
			textView.string = pretty
			textView.isEditable = false
			textView.isSelectable = true
			textView.drawsBackground = false
			textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
			textView.textContainerInset = NSSize(width: 4, height: 4)

			let scrollView = NSScrollView()
			scrollView.translatesAutoresizingMaskIntoConstraints = false
			scrollView.hasVerticalScroller = true
			scrollView.drawsBackground = false
			scrollView.borderType = .noBorder
			scrollView.documentView = textView
			contentView.addSubview(scrollView)
			jsonScrollView = scrollView

			let label = NSTextField(labelWithString: "JSON")
			label.translatesAutoresizingMaskIntoConstraints = false
			label.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
			label.textColor = .labelColor
			topRow.addArrangedSubview(label)
		} else {
			let summaryLabel = NSTextField(labelWithString: Self.summary(for: type))
			summaryLabel.translatesAutoresizingMaskIntoConstraints = false
			summaryLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
			summaryLabel.textColor = .labelColor
			summaryLabel.lineBreakMode = .byTruncatingTail
			summaryLabel.maximumNumberOfLines = 1
			summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			topRow.addArrangedSubview(summaryLabel)
		}

		let buttonRow = NSStackView()
		buttonRow.translatesAutoresizingMaskIntoConstraints = false
		buttonRow.orientation = .horizontal
		buttonRow.alignment = .centerY
		buttonRow.spacing = 8
		contentView.addSubview(buttonRow)

		for (index, action) in actions.enumerated() {
			let button = NSButton(title: action.title, target: self, action: #selector(actionButtonTapped(_:)))
			button.tag = index
			button.bezelStyle = .rounded
			if index == 0 {
				button.keyEquivalent = "\r" // 回车触发主操作
			}
			buttonRow.addArrangedSubview(button)
		}

		let hintLabel = NSTextField(labelWithString: "⏎ 执行    Esc 关闭")
		hintLabel.translatesAutoresizingMaskIntoConstraints = false
		hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
		hintLabel.textColor = .secondaryLabelColor
		contentView.addSubview(hintLabel)

		window.contentView = rootView
		var constraints: [NSLayoutConstraint] = [
			backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
			backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor),
			backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

			contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
			contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -18),
			contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
			contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12),

			topRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			topRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			topRow.topAnchor.constraint(equalTo: contentView.topAnchor),

			buttonRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),

			hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			hintLabel.centerYAnchor.constraint(equalTo: buttonRow.centerYAnchor),
			buttonRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
		]

		if let jsonScrollView {
			constraints += [
				jsonScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
				jsonScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
				jsonScrollView.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
				buttonRow.topAnchor.constraint(equalTo: jsonScrollView.bottomAnchor, constant: 10)
			]
		} else {
			constraints.append(buttonRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10))
		}

		NSLayoutConstraint.activate(constraints)

		keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self else { return event }
			if event.keyCode == 53 { // Esc
				self.closeWindow()
				return nil
			}
			if event.keyCode == 36 { // Return
				self.runPrimaryAction()
				return nil
			}
			return event
		}
	}

	func windowWillClose(_ notification: Notification) {
		if let keyDownMonitor {
			NSEvent.removeMonitor(keyDownMonitor)
			self.keyDownMonitor = nil
		}
		onClose()
	}

	func windowDidResignKey(_ notification: Notification) {
		closeWindow()
	}
}

// MARK: - 动作定义

private struct PasteFlowActionButton {
	let title: String
	let handler: () -> Void
}

private extension PasteFlowWindowController {
	static func iconName(for type: PasteFlowType) -> String {
		switch type {
		case .url: return "safari"
		case .email: return "envelope"
		case .phone: return "phone"
		case .address: return "map"
		case .ipAddress: return "network"
		case .color: return "paintpalette"
		case .dateTime: return "calendar"
		case .timestamp: return "clock"
		case .json: return "curlybraces"
		case .math: return "function"
		case .tracking: return "shippingbox"
		}
	}

	static func summary(for type: PasteFlowType) -> String {
		switch type {
		case let .url(url): return url.absoluteString
		case let .email(value): return value
		case let .phone(value): return value
		case let .address(value): return value
		case let .ipAddress(value): return value
		case let .color(color): return "\(color.hex)  ·  \(color.rgbString)"
		case let .dateTime(date): return dateFormatter.string(from: date)
		case let .timestamp(_, formatted): return formatted
		case let .json(pretty): return pretty
		case let .math(expression, result): return "\(expression) = \(formatNumber(result))"
		case let .tracking(value): return value
		}
	}

	static var dateFormatter: DateFormatter {
		let formatter = DateFormatter()
		formatter.dateStyle = .medium
		formatter.timeStyle = .short
		return formatter
	}

	static func formatNumber(_ value: Double) -> String {
		if value == value.rounded() {
			return String(Int(value))
		}
		return String(value)
	}

	static func actionButtons(for type: PasteFlowType) -> [PasteFlowActionButton] {
		switch type {
		case let .url(url):
			return [PasteFlowActionButton(title: "在浏览器打开") { NSWorkspace.shared.open(url) }]

		case let .email(value):
			return [PasteFlowActionButton(title: "撰写邮件") {
				if let url = URL(string: "mailto:\(value)") { NSWorkspace.shared.open(url) }
			}]

		case let .phone(value):
			let digits = value.filter { $0.isNumber || $0 == "+" }
			return [PasteFlowActionButton(title: "拨打") {
				if let url = URL(string: "tel:\(digits)") { NSWorkspace.shared.open(url) }
			}]

		case let .address(value):
			return [PasteFlowActionButton(title: "在地图打开") { openInMaps(query: value) }]

		case let .ipAddress(value):
			return [PasteFlowActionButton(title: "复制 IP") { copyToPasteboard(value) }]

		case let .color(color):
			return [
				PasteFlowActionButton(title: "复制 HEX") { copyToPasteboard(color.hex) },
				PasteFlowActionButton(title: "复制 RGB") { copyToPasteboard(color.rgbString) }
			]

		case .dateTime:
			return [PasteFlowActionButton(title: "添加到日历") {
				if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
			}]

		case let .timestamp(_, formatted):
			return [PasteFlowActionButton(title: "复制日期") { copyToPasteboard(formatted) }]

		case let .json(pretty):
			return [PasteFlowActionButton(title: "复制格式化 JSON") { copyToPasteboard(pretty) }]

		case let .math(_, result):
			return [PasteFlowActionButton(title: "复制结果") { copyToPasteboard(formatNumber(result)) }]

		case let .tracking(value):
			return [PasteFlowActionButton(title: "追踪物流") {
				let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
				if let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
					NSWorkspace.shared.open(url)
				}
			}]
		}
	}

	static func copyToPasteboard(_ string: String) {
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.setString(string, forType: .string)
	}

	static func openInMaps(query: String) {
		let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
		if let url = URL(string: "https://maps.apple.com/?q=\(encoded)") {
			NSWorkspace.shared.open(url)
		}
	}

}

/// 非激活面板：能成为 key window 接收回车/Esc，但不会把整个 App 激活到前台。
final class PasteFlowPanel: NSPanel {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { false }
}
