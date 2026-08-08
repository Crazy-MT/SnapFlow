import Cocoa
import ApplicationServices
import CoreGraphics
import SnapFlowKit

struct HyperSwitchWindow {
	let windowID: CGWindowID
	let title: String
	let appName: String
	let bundleIdentifier: String?
	let processID: pid_t
	let bounds: CGRect
	let icon: NSImage
	let snapshot: CGImage?
}

enum HyperSwitchWindowProvider {
	static func hasScreenCaptureAccess() -> Bool {
		if #available(macOS 10.15, *) {
			return CGPreflightScreenCaptureAccess()
		}
		return true
	}

	static func requestScreenCaptureAccessIfNeeded() {
		if #available(macOS 10.15, *), !CGPreflightScreenCaptureAccess() {
			CGRequestScreenCaptureAccess()
		}
	}

	static func visibleWindows(limit: Int = 12) -> [HyperSwitchWindow] {
		guard
			let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
				as? [[String: Any]]
		else {
			return []
		}

		return rawWindows.compactMap(makeWindow).prefix(limit).map { $0 }
	}

	static func activate(_ item: HyperSwitchWindow) {
		let application = NSRunningApplication(processIdentifier: item.processID)
		application?.activate(options: [])

		guard AXIsProcessTrusted() else { return }
		let appElement = AXUIElementCreateApplication(item.processID)
		guard let windowElement = axWindow(in: appElement, matching: item) else { return }

		AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
		AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, windowElement)
		AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
	}

	private static func makeWindow(_ info: [String: Any]) -> HyperSwitchWindow? {
		guard
			let windowID = info[kCGWindowNumber as String] as? UInt32,
			let processID = info[kCGWindowOwnerPID as String] as? pid_t,
			processID != ProcessInfo.processInfo.processIdentifier,
			let layer = info[kCGWindowLayer as String] as? Int,
			layer == 0,
			let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary
		else {
			return nil
		}

		var bounds = CGRect.zero
		CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds)
		guard bounds.width >= 80, bounds.height >= 60 else { return nil }

		let title = (info[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		let appName = (info[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		guard !appName.isEmpty else { return nil }

		let application = NSRunningApplication(processIdentifier: processID)
		let icon = application?.icon ?? NSWorkspace.shared.icon(forFileType: "app")
		icon.size = NSSize(width: 32, height: 32)

		return HyperSwitchWindow(
			windowID: CGWindowID(windowID),
			title: title.isEmpty ? "无标题窗口" : title,
			appName: appName,
			bundleIdentifier: application?.bundleIdentifier,
			processID: processID,
			bounds: bounds,
			icon: icon,
			snapshot: snapshot(for: CGWindowID(windowID))
		)
	}

	private static func snapshot(for windowID: CGWindowID) -> CGImage? {
		CGWindowListCreateImage(
			.null,
			.optionIncludingWindow,
			windowID,
			[.boundsIgnoreFraming, .bestResolution]
		)
	}

	private static func axWindow(in appElement: AXUIElement, matching item: HyperSwitchWindow) -> AXUIElement? {
		var value: CFTypeRef?
		guard
			AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
			let windows = value as? [AXUIElement]
		else {
			return nil
		}

		return windows.first { window in
			axString(window, kAXTitleAttribute) == item.title
		} ?? windows.first
	}

	private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
		var value: CFTypeRef?
		guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
			return nil
		}
		return value as? String
	}
}

final class HyperSwitchWindowController: NSWindowController, NSWindowDelegate {
	private let onClose: () -> Void
	private var windows: [HyperSwitchWindow]
	private var selectedIndex = 0
	private var keyDownMonitor: Any?
	private var localFlagsMonitor: Any?
	private var globalFlagsMonitor: Any?
	private var lastTabSelectionTime = Date.distantPast
	private var isClosing = false
	private weak var scrollView: NSScrollView?
	private weak var hintLabel: NSTextField?
	private var gridView: HyperSwitchGridView?
	private var gridHeightConstraint: NSLayoutConstraint?
	private var rowViews = [NSView]()
        private static let cardSize = NSSize(width: 240, height: 196)
	private static let cardSpacing: CGFloat = 14
        private static let initialWindowSize = NSSize(width: 720, height: 390)
        private static let windowHorizontalChrome: CGFloat = 96

	var isVisible: Bool {
		guard let window else { return false }
		return window.isVisible && !isClosing
	}

	init(onClose: @escaping () -> Void) {
		self.onClose = onClose
		self.windows = HyperSwitchWindowProvider.visibleWindows()

		let window = KeyableWindow(
			contentRect: CGRect(origin: .zero, size: Self.initialWindowSize),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.title = "HyperSwitch"
		window.center()
		window.isMovableByWindowBackground = true
		window.level = .floating
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = false
		window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

		super.init(window: window)

		window.delegate = self
		setupContentView()
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	func show() {
		isClosing = false
		SnapFlowKit.disable(.hyperSwitch)
		HyperSwitchWindowProvider.requestScreenCaptureAccessIfNeeded()
		reloadWindows()
		window?.alphaValue = 0
		window?.makeKeyAndOrderFront(nil)
		window?.layoutIfNeeded()
		updateDocumentSize()
		updateSelection()
		window?.center()
		NSApp.activate(ignoringOtherApps: true)

		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			self.window?.animator().alphaValue = 1
		}
	}

	func activateAndFocus() {
		guard let window, !isClosing else { return }
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
	}

	func selectNext() {
		let now = Date()
		guard now.timeIntervalSince(lastTabSelectionTime) > 0.08 else { return }
		lastTabSelectionTime = now
		select(offset: 1)
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

	private func setupContentView() {
		guard let window else { return }

		let contentView = NSView()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		let rootView = NSView()
		rootView.wantsLayer = true
		rootView.layer?.backgroundColor = NSColor.clear.cgColor
		let shadowView = HyperSwitchShadowView(cornerRadius: 24, padding: 28)
		shadowView.translatesAutoresizingMaskIntoConstraints = false
		let backgroundView: NSView
		let shadowPadding: CGFloat = 28

		if #available(macOS 26.0, *) {
			let glassView = NSGlassEffectView()
			glassView.translatesAutoresizingMaskIntoConstraints = false
			glassView.style = .regular
			glassView.cornerRadius = 24
			glassView.clipsToBounds = true
                        glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.10)
			glassView.contentView = contentView
			backgroundView = glassView
		} else {
			let visualEffectView = NSVisualEffectView()
			visualEffectView.translatesAutoresizingMaskIntoConstraints = false
			visualEffectView.state = .active
			visualEffectView.blendingMode = .behindWindow
                        visualEffectView.material = .popover
			visualEffectView.wantsLayer = true
			visualEffectView.layer?.cornerRadius = 24
			visualEffectView.layer?.borderWidth = 1
                        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
			visualEffectView.layer?.masksToBounds = true
			visualEffectView.addSubview(contentView)
			backgroundView = visualEffectView
		}
		rootView.addSubview(shadowView)
		rootView.addSubview(backgroundView)

		let titleLabel = NSTextField(labelWithString: "窗口切换")
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
		contentView.addSubview(titleLabel)

		let hintLabel = NSTextField(labelWithString: "按住 Option，Tab 选择，松开切换    Esc 关闭")
		hintLabel.translatesAutoresizingMaskIntoConstraints = false
		hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
		hintLabel.textColor = .secondaryLabelColor
		self.hintLabel = hintLabel
		contentView.addSubview(hintLabel)

		let gridView = HyperSwitchGridView(
			cardSize: Self.cardSize,
			spacing: Self.cardSpacing
		)
		gridView.translatesAutoresizingMaskIntoConstraints = false
		let gridHeightConstraint = gridView.heightAnchor.constraint(equalToConstant: Self.cardSize.height)
		self.gridHeightConstraint = gridHeightConstraint
		self.gridView = gridView

		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.drawsBackground = false
		scrollView.borderType = .noBorder
		scrollView.hasHorizontalScroller = false
		scrollView.hasVerticalScroller = false
		scrollView.autohidesScrollers = true
		scrollView.documentView = gridView
		self.scrollView = scrollView
		contentView.addSubview(scrollView)

		window.contentView = rootView
		NSLayoutConstraint.activate([
			backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: shadowPadding),
			backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -shadowPadding),
			backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: shadowPadding),
			backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -shadowPadding),

			shadowView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			shadowView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
			shadowView.topAnchor.constraint(equalTo: rootView.topAnchor),
			shadowView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),

			contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 20),
			contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -20),
			contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 22),
			contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -18),

			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),

			hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			hintLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
			scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

			gridView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
			gridView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
			gridView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
			gridHeightConstraint
		])

		keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self else { return event }
			switch event.keyCode {
			case 48:
				self.selectNext()
				return nil
			case 125, 124:
				self.select(offset: 1)
				return nil
			case 126, 123:
				self.select(offset: -1)
				return nil
			case 36, 76:
				self.commitSelection()
				return nil
			case 53:
				self.closeWindow()
				return nil
			default:
				return event
			}
		}

		localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			self?.commitIfCommandReleased(flags: event.modifierFlags)
			return event
		}

		globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			self?.commitIfCommandReleased(flags: event.modifierFlags)
		}

	}

	private func reloadWindows() {
		windows = HyperSwitchWindowProvider.visibleWindows()
		selectedIndex = windows.isEmpty ? -1 : 0
		updateHint()
		rowViews.forEach { $0.removeFromSuperview() }
		rowViews = windows.enumerated().map(makeRow)
		gridView?.setCards(rowViews)

		if windows.isEmpty {
			let emptyLabel = NSTextField(labelWithString: "没有可切换的窗口")
			emptyLabel.textColor = .secondaryLabelColor
			rowViews = [emptyLabel]
			gridView?.setCards(rowViews)
		}

		updateDocumentSize()
		updateSelection()
	}

	private func updateHint() {
		let hasSnapshots = windows.contains { $0.snapshot != nil }
		if !windows.isEmpty, !hasSnapshots, !HyperSwitchWindowProvider.hasScreenCaptureAccess() {
			hintLabel?.stringValue = "请在系统设置 > 隐私与安全性 > 屏幕录制中允许 SnapFlow"
		} else {
			hintLabel?.stringValue = "按住 Command，Tab 选择，松开切换    Esc 关闭"
		}
	}

	private func makeRow(index: Int, item: HyperSwitchWindow) -> NSView {
		let card = HyperSwitchCardView(index: index)
		card.translatesAutoresizingMaskIntoConstraints = true
		card.target = self
		card.action = #selector(rowClicked(_:))

		let preview = HyperSwitchPreviewView()
		preview.translatesAutoresizingMaskIntoConstraints = false
		preview.setPreview(item.snapshot, fallback: item.icon)
		card.contentView.addSubview(preview)

		let iconView = NSImageView()
		iconView.translatesAutoresizingMaskIntoConstraints = false
		iconView.image = item.icon
		card.contentView.addSubview(iconView)

		let appLabel = NSTextField(labelWithString: item.appName)
		appLabel.translatesAutoresizingMaskIntoConstraints = false
		appLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
		appLabel.lineBreakMode = .byTruncatingTail
		card.contentView.addSubview(appLabel)

		let titleLabel = NSTextField(labelWithString: item.title)
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
		titleLabel.textColor = .secondaryLabelColor
		titleLabel.lineBreakMode = .byTruncatingTail
		card.contentView.addSubview(titleLabel)

		NSLayoutConstraint.activate([
                        preview.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
                        preview.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
                        preview.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 4),
                        preview.heightAnchor.constraint(equalTo: preview.widthAnchor, multiplier: 9.0 / 16.0),

                        iconView.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
                        iconView.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
			iconView.widthAnchor.constraint(equalToConstant: 28),
			iconView.heightAnchor.constraint(equalToConstant: 28),

			appLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
                        appLabel.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
                        appLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),

                        titleLabel.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
                        titleLabel.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
			titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8)
		])

		return card
	}

	private func select(offset: Int) {
		guard !windows.isEmpty else { return }
		selectedIndex = (selectedIndex + offset + windows.count) % windows.count
		updateSelection()
	}

	private func updateSelection() {
		for (index, rowView) in rowViews.enumerated() {
			(rowView as? HyperSwitchCardView)?.setSelected(index == selectedIndex)
		}
		scrollSelectedCardIntoView()
	}

	private func commitSelection() {
		guard !isClosing, windows.indices.contains(selectedIndex) else { return }
		let item = windows[selectedIndex]
		closeWindow()
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
			HyperSwitchWindowProvider.activate(item)
		}
	}

	private func commitIfCommandReleased(flags: NSEvent.ModifierFlags) {
		let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)
		guard !deviceFlags.contains(.command) else { return }
		commitSelection()
	}

	private func updateDocumentSize() {
		guard let scrollView, let gridView else { return }
                window?.layoutIfNeeded()
                let screenWidth = window?.screen?.visibleFrame.width ?? NSScreen.main?.visibleFrame.width ?? 1440
                let maxWindowWidth = max(420, screenWidth - 80)
                let maxGridWidth = max(1, maxWindowWidth - Self.windowHorizontalChrome)
                let width = gridView.preferredWidth(maxWidth: maxGridWidth)
                let height = gridView.preferredHeight(for: width)
		gridHeightConstraint?.constant = height
                resizeWindowToFitGrid(width: width, height: height)
		gridView.layoutSubtreeIfNeeded()
	}

        private func resizeWindowToFitGrid(width gridWidth: CGFloat, height gridHeight: CGFloat) {
		guard let window, let scrollView else { return }
		window.layoutIfNeeded()

                let screenWidth = window.screen?.visibleFrame.width ?? NSScreen.main?.visibleFrame.width ?? 1440
		let screenHeight = window.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
                let maxWindowWidth = min(screenWidth - 80, 1480)
		let maxWindowHeight = min(screenHeight - 80, 780)
		let chromeHeight = window.frame.height - scrollView.frame.height
                let targetWidth = min(maxWindowWidth, ceil(Self.windowHorizontalChrome + gridWidth))
		let targetHeight = min(maxWindowHeight, ceil(chromeHeight + gridHeight))
		scrollView.hasVerticalScroller = gridHeight > scrollView.contentView.bounds.height + 0.5
                guard
                        abs(window.frame.width - targetWidth) > 0.5 ||
                        abs(window.frame.height - targetHeight) > 0.5
                else {
                        return
                }

		var frame = window.frame
                frame.origin.x += (frame.width - targetWidth) / 2
		frame.origin.y += frame.height - targetHeight
                frame.size.width = targetWidth
		frame.size.height = targetHeight
		window.setFrame(frame, display: true, animate: false)
	}

	private func scrollSelectedCardIntoView() {
		guard
			let scrollView,
			rowViews.indices.contains(selectedIndex)
		else {
			return
		}

		let row = rowViews[selectedIndex]
		scrollView.contentView.scrollToVisible(row.frame)
		scrollView.reflectScrolledClipView(scrollView.contentView)
	}

	@objc private func rowClicked(_ sender: HyperSwitchCardView) {
		selectedIndex = sender.index
		commitSelection()
	}

	func windowWillClose(_ notification: Notification) {
		if let keyDownMonitor {
			NSEvent.removeMonitor(keyDownMonitor)
			self.keyDownMonitor = nil
		}
		if let localFlagsMonitor {
			NSEvent.removeMonitor(localFlagsMonitor)
			self.localFlagsMonitor = nil
		}
		if let globalFlagsMonitor {
			NSEvent.removeMonitor(globalFlagsMonitor)
			self.globalFlagsMonitor = nil
		}
		SnapFlowKit.enable(.hyperSwitch)
		onClose()
	}

	func windowDidResignKey(_ notification: Notification) {
		closeWindow()
	}
}

final class HyperSwitchGridView: NSView {
	private let cardSize: NSSize
	private let spacing: CGFloat
        private let preferredColumnCount = 7
        private let leadingInset: CGFloat = 20
	private var cards = [NSView]()

	init(cardSize: NSSize, spacing: CGFloat) {
		self.cardSize = cardSize
		self.spacing = spacing
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override var isFlipped: Bool {
		true
	}

	func setCards(_ cards: [NSView]) {
		self.cards.forEach { $0.removeFromSuperview() }
		self.cards = cards
		cards.forEach { addSubview($0) }
		needsLayout = true
	}

        func preferredWidth(maxWidth: CGFloat) -> CGFloat {
                let columnCount = min(max(cards.count, 1), preferredColumnCount)
                let idealWidth = CGFloat(columnCount) * cardSize.width
                        + CGFloat(max(columnCount - 1, 0)) * spacing
                        + leadingInset
                return min(maxWidth, idealWidth)
        }

	func preferredHeight(for width: CGFloat) -> CGFloat {
                let itemCount = max(cards.count, 1)
                let columnCount = min(itemCount, preferredColumnCount)
		let rowCount = Int(ceil(Double(max(cards.count, 1)) / Double(columnCount)))
		return CGFloat(rowCount) * cardSize.height + CGFloat(max(rowCount - 1, 0)) * spacing
	}

	override func layout() {
		super.layout()
                let columnCount = min(max(cards.count, 1), preferredColumnCount)
                let totalSpacing = CGFloat(max(columnCount - 1, 0)) * spacing
                let availableWidth = max(0, bounds.width - leadingInset)
                let cardWidth = max(0, (availableWidth - totalSpacing) / CGFloat(columnCount))
		for (index, card) in cards.enumerated() {
			let column = index % columnCount
			let row = index / columnCount
                        let itemsInRow = min(columnCount, max(cards.count - row * columnCount, 0))
                        let rowWidth = CGFloat(itemsInRow) * cardWidth + CGFloat(max(itemsInRow - 1, 0)) * spacing
                        let rowInset = max(0, (availableWidth - rowWidth) / 2)
			card.frame = NSRect(
                                x: leadingInset + rowInset + CGFloat(column) * (cardWidth + spacing),
				y: CGFloat(row) * (cardSize.height + spacing),
                                width: cardWidth,
				height: cardSize.height
			)
		}
	}
}

final class HyperSwitchCardView: NSView {
	let index: Int
	let contentView = NSView()
	weak var target: AnyObject?
	var action: Selector?
	private weak var glassView: NSView?

	init(index: Int) {
		self.index = index
		super.init(frame: .zero)
		wantsLayer = true
		layer?.cornerRadius = 14
		layer?.shadowColor = NSColor.black.cgColor
		layer?.shadowOpacity = 0
		layer?.shadowRadius = 10
		layer?.shadowOffset = CGSize(width: 0, height: -3)

		contentView.translatesAutoresizingMaskIntoConstraints = false
		if #available(macOS 26.0, *) {
			let glassView = NSGlassEffectView()
			glassView.translatesAutoresizingMaskIntoConstraints = false
				glassView.style = .clear
				glassView.cornerRadius = 14
				glassView.clipsToBounds = true
                                glassView.tintColor = NSColor.white.withAlphaComponent(0.10)
				glassView.contentView = contentView
			self.glassView = glassView
			addSubview(glassView)
			NSLayoutConstraint.activate([
				glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
				glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
				glassView.topAnchor.constraint(equalTo: topAnchor),
				glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
				contentView.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
				contentView.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
				contentView.topAnchor.constraint(equalTo: glassView.topAnchor),
				contentView.bottomAnchor.constraint(equalTo: glassView.bottomAnchor)
			])
		} else {
			layer?.cornerRadius = 14
			layer?.borderWidth = 1
                        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
                        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
			addSubview(contentView)
			NSLayoutConstraint.activate([
				contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
				contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
				contentView.topAnchor.constraint(equalTo: topAnchor),
				contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
			])
		}
		addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func layout() {
		super.layout()
		layer?.shadowPath = CGPath(
			roundedRect: bounds,
			cornerWidth: 14,
			cornerHeight: 14,
			transform: nil
		)
	}

	@objc private func clicked() {
		guard let action else { return }
		NSApp.sendAction(action, to: target, from: self)
	}

	func setSelected(_ selected: Bool) {
                let selectedTint = NSColor(calibratedRed: 0.56, green: 0.76, blue: 0.98, alpha: 1)
		if #available(macOS 26.0, *), let glassView = glassView as? NSGlassEffectView {
			glassView.style = selected ? .regular : .clear
			glassView.tintColor = selected
                                ? selectedTint.withAlphaComponent(0.18)
                                : NSColor.white.withAlphaComponent(0.10)
		}
		layer?.backgroundColor = selected
                        ? selectedTint.withAlphaComponent(0.12).cgColor
			: NSColor.clear.cgColor
		layer?.borderColor = selected
                        ? selectedTint.withAlphaComponent(0.62).cgColor
                        : NSColor.white.withAlphaComponent(0.18).cgColor
		layer?.shadowOpacity = selected ? 0.24 : 0
	}
}

final class HyperSwitchShadowView: NSView {
	private let cornerRadius: CGFloat
	private let padding: CGFloat

	init(cornerRadius: CGFloat, padding: CGFloat) {
		self.cornerRadius = cornerRadius
		self.padding = padding
		super.init(frame: .zero)
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		let path = NSBezierPath(
			roundedRect: bounds.insetBy(dx: padding, dy: padding),
			xRadius: cornerRadius,
			yRadius: cornerRadius
		)
		NSGraphicsContext.saveGraphicsState()
		let shadow = NSShadow()
		shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
		shadow.shadowBlurRadius = 18
		shadow.shadowOffset = NSSize(width: 0, height: -6)
		shadow.set()
		NSColor.black.setFill()
		path.fill()
		NSGraphicsContext.restoreGraphicsState()
		NSGraphicsContext.saveGraphicsState()
		NSGraphicsContext.current?.compositingOperation = .clear
		path.fill()
		NSGraphicsContext.restoreGraphicsState()
	}
}

final class HyperSwitchPreviewView: NSView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		wantsLayer = true
		layer?.cornerRadius = 8
		layer?.masksToBounds = true
		layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
		layer?.contentsGravity = .resizeAspect
		layer?.minificationFilter = .trilinear
		layer?.magnificationFilter = .linear
	}

	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		layer?.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
	}

	func setPreview(_ snapshot: CGImage?, fallback icon: NSImage) {
		if let snapshot {
                        layer?.contentsGravity = .resizeAspectFill
			layer?.contents = snapshot
			return
		}

		var rect = NSRect(origin: .zero, size: icon.size)
		layer?.contents = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil)
		layer?.contentsGravity = .center
	}
}
