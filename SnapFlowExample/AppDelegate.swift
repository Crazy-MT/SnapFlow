import Cocoa
import ApplicationServices
import CoreGraphics
import SwiftUI
import SnapFlowKit

extension SnapFlowKit.Name {
	static let clipboardHistory = Self(
		"clipboardHistory",
		default: .init(.v, modifiers: [.command, .shift])
	)
}

@NSApplicationMain
final class AppDelegate: NSObject, NSApplicationDelegate {
	private var statusItem: NSStatusItem!
	private var statusMenu: NSMenu!
	private var shortcutsPopover: NSPopover!
	private var searchWindowController: SearchWindowController?
	private var doubleCommandHotKey: DoubleCommandHotKey?
	private let clipboardHistoryManager = ClipboardHistoryManager(maxItems: 50)
	private let shortcutActionsModel = ShortcutActionsModel()
	private var clipboardHistoryWindowController: ClipboardHistoryWindowController?
	private var pasteFlowWindowController: PasteFlowWindowController?

	func applicationDidFinishLaunching(_ notification: Notification) {
		setupStatusBar()
		setupShortcutsPopover()
		createMenus()
		requestKeyboardMonitoringPermissionsIfNeeded()
		setupDoubleCommandDetection()
		setupClipboardHistory()
	}
	
	private func requestKeyboardMonitoringPermissionsIfNeeded() {
		guard !AXIsProcessTrusted() else {
			return
		}

		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
	}

	private func setupStatusBar() {
		statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

		if let button = statusItem.button {
			if let image = NSImage(named: NSImage.Name("MenuBarIcon")) {
				image.size = NSSize(width: 18, height: 18)
				image.isTemplate = false
				button.image = image
				button.imagePosition = .imageOnly
			} else if #available(macOS 11.0, *) {
				button.image = NSImage(systemSymbolName: "command", accessibilityDescription: "SnapFlowKit")
			} else {
				button.title = "⌘"
			}
			button.target = self
			button.action = #selector(toggleShortcutsPopover)
			button.sendAction(on: [.leftMouseUp, .rightMouseUp])
		}

		let menu = NSMenu()
		menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
		statusMenu = menu
	}

	private func setupShortcutsPopover() {
		let popover = NSPopover()
		popover.behavior = .transient
		popover.animates = true
		popover.contentSize = NSSize(width: 560, height: 420)
		popover.contentViewController = NSHostingController(rootView: ContentView(model: shortcutActionsModel))
		shortcutsPopover = popover
	}

	@objc private func toggleShortcutsPopover() {
		guard let button = statusItem.button else { return }
		if NSApp.currentEvent?.type == .rightMouseUp {
			statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
			return
		}

		if shortcutsPopover.isShown {
			shortcutsPopover.performClose(nil)
		} else {
			NSApp.activate(ignoringOtherApps: true)
			shortcutsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
			shortcutsPopover.contentViewController?.view.window?.makeKey()
		}
	}

	@objc private func quitApp() {
		NSApp.terminate(nil)
	}

	func createMenus() {
		let testMenuItem = NSMenuItem()
		NSApp.mainMenu?.addItem(testMenuItem)

		let testMenu = NSMenu()
		testMenu.title = "Test"
		testMenuItem.submenu = testMenu

		let shortcut1 = NSMenuItem()
		shortcut1.title = "Shortcut 1"
		shortcut1.action = #selector(shortcutAction1)
		shortcut1.setShortcut(for: .testShortcut1)
		testMenu.addItem(shortcut1)

		let shortcut2 = NSMenuItem()
		shortcut2.title = "Shortcut 2"
		shortcut2.action = #selector(shortcutAction2)
		shortcut2.setShortcut(for: .testShortcut2)
		testMenu.addItem(shortcut2)
	}

	@objc
	func shortcutAction1(_ sender: NSMenuItem) {
		let alert = NSAlert()
		alert.messageText = "Shortcut 1 menu item action triggered!"
		alert.runModal()
	}

	@objc
	func shortcutAction2(_ sender: NSMenuItem) {
		let alert = NSAlert()
		alert.messageText = "Shortcut 2 menu item action triggered!"
		alert.runModal()
	}
	
	private func setupDoubleCommandDetection() {
		doubleCommandHotKey = DoubleCommandHotKey(threshold: 0.5) { [weak self] in
			self?.showSearchWindow()
		}
		doubleCommandHotKey?.start()
	}
	
	private func showSearchWindow() {
		if let controller = searchWindowController, controller.isVisible {
			controller.activateAndFocus()
			return
		}
		
		let controller = SearchWindowController(
			onSearch: handleSearch,
			onClose: { [weak self] in
				self?.searchWindowController = nil
			}
		)
		searchWindowController = controller
		controller.show()
	}

	private func setupClipboardHistory() {
		clipboardHistoryManager.onNewClipboardText = { [weak self] text in
			self?.showPasteFlowPanel(for: text)
		}
		clipboardHistoryManager.start()
		SnapFlowKit.onKeyDown(for: .clipboardHistory) { [weak self] in
			self?.handleClipboardHistoryHotKey()
		}
	}

	private func showPasteFlowPanel(for text: String) {
		guard let type = PasteFlowDetector.detect(text) else { return }

		pasteFlowWindowController?.closeWindow()

		let controller = PasteFlowWindowController(type: type) { [weak self] in
			self?.pasteFlowWindowController = nil
		}
		pasteFlowWindowController = controller
		controller.show()
	}
	
	private func handleClipboardHistoryHotKey() {
		if let controller = clipboardHistoryWindowController, controller.isVisible {
			controller.activateAndFocus()
			controller.selectNext()
			return
		}

		let previousApplication = NSWorkspace.shared.frontmostApplication
		
		let controller = ClipboardHistoryWindowController(
			items: clipboardHistoryManager.items,
			onCommit: { [weak self] item in
				self?.commitClipboardHistoryItem(item, previousApplication: previousApplication)
			},
			onClose: { [weak self] in
				self?.clipboardHistoryWindowController = nil
			}
		)
		
		clipboardHistoryWindowController = controller
		controller.show()
	}

	private func commitClipboardHistoryItem(_ item: ClipboardHistoryItem, previousApplication: NSRunningApplication?) {
		clipboardHistoryManager.setClipboardItem(item)
		clipboardHistoryWindowController?.closeWindow()

		DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
			previousApplication?.activate(options: [])
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
				self.sendPasteShortcut()
			}
		}
	}

	private func sendPasteShortcut() {
		let source = CGEventSource(stateID: .hidSystemState)
		let keyCode = CGKeyCode(9)
		let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
		let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

		keyDown?.flags = .maskCommand
		keyUp?.flags = .maskCommand
		keyDown?.post(tap: .cghidEventTap)
		keyUp?.post(tap: .cghidEventTap)
	}
	
	private func handleSearch(_ query: String) {
		searchWindowController?.closeWindow()
		
		let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
		
		if trimmedQuery.hasPrefix("pub ") {
			let searchTerm = trimmedQuery.dropFirst(4).trimmingCharacters(in: .whitespaces)
			if let url = URL(string: "https://pub.dev/packages?q=\(searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm)") {
				NSWorkspace.shared.open(url)
			}
		} else if trimmedQuery.hasPrefix("github ") {
			let searchTerm = trimmedQuery.dropFirst(7).trimmingCharacters(in: .whitespaces)
			if let url = URL(string: "https://github.com/search?q=\(searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? searchTerm)&type=repositories") {
				NSWorkspace.shared.open(url)
			}
		} else {
			if let url = SearchEngine.saved.searchURL(for: trimmedQuery) {
				NSWorkspace.shared.open(url)
			}
		}
	}
}

final class DoubleCommandHotKey {
	private let threshold: TimeInterval
	private let onTrigger: () -> Void
	private var pressCount = 0
	private var lastPressTime = Date.distantPast
	private var isCommandDown = false
	private var didShowPermissionsAlert = false
	private var localMonitor: Any?
	private var globalMonitor: Any?
	private var eventTap: CFMachPort?
	private var runLoopSource: CFRunLoopSource?

	init(threshold: TimeInterval, onTrigger: @escaping () -> Void) {
		self.threshold = threshold
		self.onTrigger = onTrigger
	}

	deinit {
		stop()
	}

	func start() {
		stop()

		ensurePermissionsIfPossible()
		
		if installEventTap() {
			return
		}

		localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			self?.handle(flags: event.modifierFlags)
			return event
		}

		globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
			self?.handle(flags: event.modifierFlags)
		}
	}

	func stop() {
		if let localMonitor {
			NSEvent.removeMonitor(localMonitor)
			self.localMonitor = nil
		}

		if let globalMonitor {
			NSEvent.removeMonitor(globalMonitor)
			self.globalMonitor = nil
		}

		if let runLoopSource {
			CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
			self.runLoopSource = nil
		}

		if let eventTap {
			CGEvent.tapEnable(tap: eventTap, enable: false)
			CFMachPortInvalidate(eventTap)
			self.eventTap = nil
		}
	}

	private func installEventTap() -> Bool {
		guard AXIsProcessTrusted() else {
			showPermissionsAlertIfNeeded()
			return false
		}
		
		let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

		let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
			guard
				type == .flagsChanged,
				let userInfo
			else {
				return Unmanaged.passUnretained(cgEvent)
			}

			let instance = Unmanaged<DoubleCommandHotKey>.fromOpaque(userInfo).takeUnretainedValue()
			let flags = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
			instance.handle(flags: flags)
			return Unmanaged.passUnretained(cgEvent)
		}

		guard let eventTap = CGEvent.tapCreate(
			tap: .cgSessionEventTap,
			place: .headInsertEventTap,
			options: .listenOnly,
			eventsOfInterest: flagsChangedMask,
			callback: callback,
			userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
		) else {
			return false
		}

		self.eventTap = eventTap

		let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
		self.runLoopSource = runLoopSource

		CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
		CGEvent.tapEnable(tap: eventTap, enable: true)

		return true
	}
	
	private func ensurePermissionsIfPossible() {
		guard !AXIsProcessTrusted() else {
			return
		}

		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
		showPermissionsAlertIfNeeded()
	}
	
	private func showPermissionsAlertIfNeeded() {
		guard !didShowPermissionsAlert else { return }
		didShowPermissionsAlert = true
		
		DispatchQueue.main.async {
			let alert = NSAlert()
			alert.messageText = "需要开启权限才能全局监听双击 ⌘"
			alert.informativeText = "请在 系统设置 → 隐私与安全性 中，为此 App 开启“辅助功能”与“输入监控”。"
			alert.addButton(withTitle: "打开系统设置")
			alert.addButton(withTitle: "稍后")
			let response = alert.runModal()
			guard response == .alertFirstButtonReturn else { return }
			if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
				NSWorkspace.shared.open(url)
			}
		}
	}

	private func handle(flags: NSEvent.ModifierFlags) {
		let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)
		let commandNowDown = deviceIndependentFlags.contains(.command)

		if commandNowDown, !isCommandDown {
			isCommandDown = true
			handleCommandDown()
			return
		}

		if !commandNowDown, isCommandDown {
			isCommandDown = false
		}
	}

	private func handleCommandDown() {
		let now = Date()
		let timeSinceLastPress = now.timeIntervalSince(lastPressTime)

		if timeSinceLastPress <= threshold {
			pressCount += 1
		} else {
			pressCount = 1
		}

		lastPressTime = now

		guard pressCount >= 2 else {
			return
		}

		pressCount = 0
		lastPressTime = Date.distantPast

		DispatchQueue.main.async { [onTrigger] in
			onTrigger()
		}
	}
}

final class KeyableWindow: NSWindow {
	override var canBecomeKey: Bool { true }
	override var canBecomeMain: Bool { true }
}

class SearchWindowController: NSWindowController, NSWindowDelegate {
	private let onSearch: (String) -> Void
	private let onClose: () -> Void
	private var searchField: NSSearchField?
	private var searchEnginePopUpButton: NSPopUpButton?
	private var keyDownMonitor: Any?
	private var isClosing = false
	private weak var backgroundView: NSVisualEffectView?
	
	var isVisible: Bool {
		guard let window else { return false }
		return window.isVisible && !isClosing
	}
	
	init(onSearch: @escaping (String) -> Void, onClose: @escaping () -> Void) {
		self.onSearch = onSearch
		self.onClose = onClose
		let window = KeyableWindow(
			contentRect: CGRect(x: 0, y: 0, width: 760, height: 86),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.title = "Quick Search"
		window.center()
		window.isMovableByWindowBackground = true
		window.level = .floating
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = true
		window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
		super.init(window: window)
		
		window.delegate = self
		setupContentView()
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
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
		self.backgroundView = backgroundView
		rootView.addSubview(backgroundView)
		
		let contentView = NSView()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(contentView)
		
		let row = NSStackView()
		row.translatesAutoresizingMaskIntoConstraints = false
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 10
		contentView.addSubview(row)
		
		if #available(macOS 11.0, *) {
			let iconView = NSImageView()
			iconView.translatesAutoresizingMaskIntoConstraints = false
			iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
			iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
			iconView.contentTintColor = .secondaryLabelColor
			row.addArrangedSubview(iconView)
			NSLayoutConstraint.activate([
				iconView.widthAnchor.constraint(equalToConstant: 22),
				iconView.heightAnchor.constraint(equalToConstant: 22)
			])
		} else {
			let label = NSTextField(labelWithString: "🔍")
			label.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
			label.textColor = .secondaryLabelColor
			row.addArrangedSubview(label)
		}
		
		let searchField = NSSearchField()
		searchField.translatesAutoresizingMaskIntoConstraints = false
		searchField.placeholderString = "搜索…（pub xxx / github xxx / 直接回车）"
		searchField.font = NSFont.systemFont(ofSize: 18, weight: .medium)
		searchField.focusRingType = .none
		searchField.isBezeled = false
		searchField.isBordered = false
		searchField.drawsBackground = false
		searchField.delegate = self
		self.searchField = searchField
		row.addArrangedSubview(searchField)

		let searchEnginePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
		searchEnginePopUpButton.translatesAutoresizingMaskIntoConstraints = false
		for searchEngine in SearchEngine.allCases {
			searchEnginePopUpButton.addItem(withTitle: searchEngine.title)
			searchEnginePopUpButton.lastItem?.representedObject = searchEngine.rawValue
		}
		searchEnginePopUpButton.selectItem(withTitle: SearchEngine.saved.title)
		searchEnginePopUpButton.target = self
		searchEnginePopUpButton.action = #selector(searchEngineChanged)
		self.searchEnginePopUpButton = searchEnginePopUpButton
		row.addArrangedSubview(searchEnginePopUpButton)
		
		let hintLabel = NSTextField(labelWithString: "⏎ 搜索    Esc 关闭")
		hintLabel.translatesAutoresizingMaskIntoConstraints = false
		hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
		hintLabel.textColor = .secondaryLabelColor
		contentView.addSubview(hintLabel)
		
		window.contentView = rootView
		NSLayoutConstraint.activate([
			backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
			backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor),
			backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
			
			contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
			contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -18),
			contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
			contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12),
			
			row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			row.topAnchor.constraint(equalTo: contentView.topAnchor),
			
			hintLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
			hintLabel.topAnchor.constraint(equalTo: row.bottomAnchor, constant: 6),
			hintLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
		])
		
		if let cell = searchField.cell as? NSSearchFieldCell {
			cell.searchButtonCell?.isTransparent = true
			cell.cancelButtonCell?.isTransparent = true
		}
		
		keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			if event.keyCode == 53 {
				self?.closeWindow()
				return nil
			}
			return event
		}
	}

	@objc
	private func searchEngineChanged() {
		guard
			let rawValue = searchEnginePopUpButton?.selectedItem?.representedObject as? String,
			let searchEngine = SearchEngine(rawValue: rawValue)
		else {
			return
		}

		SearchEngine.saved = searchEngine
	}
	
	func show() {
		isClosing = false
		window?.alphaValue = 0
		window?.center()
		window?.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			self.window?.animator().alphaValue = 1
		}
		DispatchQueue.main.async { [weak self] in
			self?.window?.makeFirstResponder(self?.searchField)
		}
	}
	
	func activateAndFocus() {
		guard let window, !isClosing else { return }
		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
		DispatchQueue.main.async { [weak self] in
			self?.window?.makeFirstResponder(self?.searchField)
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

extension SearchWindowController: NSSearchFieldDelegate {
	func controlTextDidBeginEditing(_ obj: Notification) {
		backgroundView?.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.7).cgColor
	}
	
	func controlTextDidEndEditing(_ obj: Notification) {
		backgroundView?.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
		if let text = searchField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
			onSearch(text)
			closeWindow()
		}
	}
	
	func textField(_ textField: NSTextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\r" {
			let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			if !text.isEmpty {
				onSearch(text)
				closeWindow()
			}
			return false
		}
		return true
	}
}

final class ClipboardHistoryManager {
	private let pasteboard = NSPasteboard.general
	private let maxItems: Int
	private(set) var items: [ClipboardHistoryItem] = []
	private var lastChangeCount: Int
	private var timer: Timer?

	/// 轮询发现新复制的文本时回调。
	/// 仅在轮询路径触发，不在 `setClipboardItem`（用户主动回写历史）时触发。
	var onNewClipboardText: ((String) -> Void)?
	
	init(maxItems: Int) {
		self.maxItems = maxItems
		self.lastChangeCount = pasteboard.changeCount
	}
	
	func start() {
		stop()
		let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
			self?.pollPasteboard()
		}
		timer.tolerance = 0.1
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}
	
	func stop() {
		timer?.invalidate()
		timer = nil
	}
	
	func setClipboardItem(_ item: ClipboardHistoryItem) {
		guard let item = normalizedItem(item), writeItemToPasteboard(item) else { return }
		lastChangeCount = pasteboard.changeCount
		
		items = ClipboardHistorySelection.inserting(
			item,
			into: items,
			maxItems: maxItems
		)
	}
	
	private func pollPasteboard() {
		let changeCount = pasteboard.changeCount
		guard changeCount != lastChangeCount else { return }
		lastChangeCount = changeCount
		
		guard let item = itemFromPasteboard(source: currentSource()) else { return }
		
		if items.first?.content == item.content { return }
		
		items = ClipboardHistorySelection.inserting(
			item,
			into: items,
			maxItems: maxItems
		)

		if case let .text(text) = item.content {
			onNewClipboardText?(text)
		}
	}

	private func itemFromPasteboard(source: ClipboardHistorySource) -> ClipboardHistoryItem? {
		if let urls = pasteboard.readObjects(
			forClasses: [NSURL.self],
			options: [.urlReadingFileURLsOnly: true]
		) as? [URL], !urls.isEmpty {
			return ClipboardHistoryItem(content: .files(urls), source: source)
		}

		if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), !imageData.isEmpty {
			return ClipboardHistoryItem(content: .image(imageData), source: source)
		}

		guard let string = pasteboard.string(forType: .string) else { return nil }
		let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		return ClipboardHistoryItem(content: .text(trimmed), source: source)
	}

	private func writeItemToPasteboard(_ item: ClipboardHistoryItem) -> Bool {
		pasteboard.clearContents()

		switch item.content {
		case let .text(text):
			return pasteboard.setString(text, forType: .string)
		case let .image(data):
			if let image = NSImage(data: data) {
				return pasteboard.writeObjects([image])
			}

			return pasteboard.setData(data, forType: .tiff)
		case let .files(urls):
			return pasteboard.writeObjects(urls as [NSURL])
		}
	}

	private func normalizedItem(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem? {
		switch item.content {
		case let .text(text):
			let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !trimmed.isEmpty else { return nil }
			return ClipboardHistoryItem(content: .text(trimmed), source: item.source)
		case let .image(data):
			guard !data.isEmpty else { return nil }
			return item
		case let .files(urls):
			guard !urls.isEmpty else { return nil }
			return item
		}
	}

	private func currentSource() -> ClipboardHistorySource {
		let application = NSWorkspace.shared.frontmostApplication
		return ClipboardHistorySource(
			appName: application?.localizedName,
			bundleIdentifier: application?.bundleIdentifier,
			bundleURL: application?.bundleURL
		)
	}
}

final class ClipboardHistoryWindowController: NSWindowController, NSWindowDelegate {
	private let onCommit: (ClipboardHistoryItem) -> Void
	private let onClose: () -> Void
	private var items: [ClipboardHistoryItem]
	private var collectionView: NSCollectionView?
	private var keyDownMonitor: Any?
	private var isClosing = false
	private weak var backgroundView: NSVisualEffectView?
	
	var isVisible: Bool {
		guard let window else { return false }
		return window.isVisible && !isClosing
	}
	
	init(
		items: [ClipboardHistoryItem],
		onCommit: @escaping (ClipboardHistoryItem) -> Void,
		onClose: @escaping () -> Void
	) {
		self.items = items
		self.onCommit = onCommit
		self.onClose = onClose
		
		let window = KeyableWindow(
			contentRect: CGRect(x: 0, y: 0, width: 760, height: 260),
			styleMask: [.borderless],
			backing: .buffered,
			defer: false
		)
		window.title = "Clipboard History"
		window.center()
		window.isMovableByWindowBackground = true
		window.level = .floating
		window.isOpaque = false
		window.backgroundColor = .clear
		window.hasShadow = true
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
		window?.alphaValue = 0
		window?.center()
		reloadAndSelectFirst()
		activateAndFocus()
		
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.12
			self.window?.animator().alphaValue = 1
		}
	}

	func activateAndFocus() {
		guard let window, !isClosing else { return }
		NSApp.activate(ignoringOtherApps: true)
		window.makeKeyAndOrderFront(nil)
		
		DispatchQueue.main.async { [weak self] in
			self?.window?.makeFirstResponder(self?.collectionView)
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
	
	func selectNext() {
		selectItem(at: ClipboardHistorySelection.nextIndex(current: selectedIndex, count: items.count))
	}
	
	private func reloadAndSelectFirst() {
		collectionView?.reloadData()
		if !items.isEmpty {
			selectItem(at: 0)
		}
	}
	
	private func commitSelectedRow() {
		commitItem(at: selectedIndex)
	}
	
	private var selectedIndex: Int {
		collectionView?.selectionIndexPaths.first?.item ?? -1
	}

	private func selectPrevious() {
		selectItem(at: ClipboardHistorySelection.previousIndex(current: selectedIndex, count: items.count))
	}

	private func selectItem(at index: Int) {
		guard let collectionView, index >= 0, index < items.count else { return }
		let indexPaths = Set(
			ClipboardHistorySelection
				.replacingSelection(with: index, count: items.count)
				.map { IndexPath(item: $0, section: 0) }
		)

		collectionView.deselectAll(nil)
		collectionView.selectItems(at: indexPaths, scrollPosition: .centeredHorizontally)
		collectionView.scrollToItems(at: indexPaths, scrollPosition: .centeredHorizontally)
	}

	private func commitItem(at index: Int) {
		guard index >= 0, index < items.count else { return }
		onCommit(items[index])
	}
	
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
		self.backgroundView = backgroundView
		rootView.addSubview(backgroundView)
		
		let contentView = NSView()
		contentView.translatesAutoresizingMaskIntoConstraints = false
		backgroundView.addSubview(contentView)
		
		let titleLabel = NSTextField(labelWithString: "剪切板历史（最多 50 条）")
		titleLabel.translatesAutoresizingMaskIntoConstraints = false
		titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
		titleLabel.textColor = .labelColor
		contentView.addSubview(titleLabel)
		
		let hintLabel = NSTextField(labelWithString: "⌘⇧V 切换    ⏎ 粘贴到原输入框    Esc 关闭")
		hintLabel.translatesAutoresizingMaskIntoConstraints = false
		hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
		hintLabel.textColor = .secondaryLabelColor
		contentView.addSubview(hintLabel)
		
		let scrollView = NSScrollView()
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		scrollView.hasVerticalScroller = false
		scrollView.hasHorizontalScroller = true
		scrollView.borderType = .noBorder
		scrollView.drawsBackground = false
		contentView.addSubview(scrollView)
		
		let layout = NSCollectionViewFlowLayout()
		layout.scrollDirection = .horizontal
		layout.itemSize = NSSize(width: 220, height: 148)
		layout.minimumInteritemSpacing = 10
		layout.minimumLineSpacing = 10
		layout.sectionInset = NSEdgeInsets(top: 2, left: 2, bottom: 8, right: 2)
		
		let collectionView = ClipboardHistoryCollectionView()
		collectionView.translatesAutoresizingMaskIntoConstraints = false
		collectionView.collectionViewLayout = layout
		collectionView.backgroundColors = [.clear]
		collectionView.isSelectable = true
		collectionView.allowsMultipleSelection = false
		collectionView.dataSource = self
		collectionView.delegate = self
		collectionView.onItemClick = { [weak self] index in
			self?.commitItem(at: index)
		}
		collectionView.register(
			ClipboardHistoryItemView.self,
			forItemWithIdentifier: ClipboardHistoryItemView.identifier
			)
		
		scrollView.documentView = collectionView
		self.collectionView = collectionView
		
		window.contentView = rootView
		NSLayoutConstraint.activate([
			backgroundView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
			backgroundView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
			backgroundView.topAnchor.constraint(equalTo: rootView.topAnchor),
			backgroundView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
			
			contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 18),
			contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -18),
			contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 14),
			contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -12),
			
			titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
			
			hintLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			hintLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
			
			scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
			scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
			scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
		])
		
		keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self else { return event }
			
			if event.keyCode == 53 {
				self.closeWindow()
				return nil
			}
			
			if event.keyCode == 36 {
				self.commitSelectedRow()
				return nil
			}
			
			if event.keyCode == 125 {
				self.selectNext()
				return nil
			}
			
			if event.keyCode == 124 {
				self.selectNext()
				return nil
			}

			if event.keyCode == 123 || event.keyCode == 126 {
				self.selectPrevious()
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

extension ClipboardHistoryWindowController: NSCollectionViewDataSource, NSCollectionViewDelegate {
	func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
		items.count
	}

	func collectionView(
		_ collectionView: NSCollectionView,
		itemForRepresentedObjectAt indexPath: IndexPath
	) -> NSCollectionViewItem {
		let item = collectionView.makeItem(withIdentifier: ClipboardHistoryItemView.identifier, for: indexPath)
		guard let historyItem = item as? ClipboardHistoryItemView else { return item }
		historyItem.item = items[indexPath.item]
		return historyItem
	}
}

final class ClipboardHistoryCollectionView: NSCollectionView {
	var onItemClick: ((Int) -> Void)?

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		if let index = indexPathForItem(at: point)?.item {
			onItemClick?(index)
			return
		}

		super.mouseDown(with: event)
	}
}

final class ClipboardHistoryItemView: NSCollectionViewItem {
	static let identifier = NSUserInterfaceItemIdentifier("ClipboardHistoryItem")
	private let sourceIconView = NSImageView()
	private let sourceLabel = NSTextField(labelWithString: "")
	private let previewImageView = NSImageView()
	private let label = NSTextField(labelWithString: "")
	private var previewHeightConstraint: NSLayoutConstraint?

	var item: ClipboardHistoryItem? {
		didSet {
			configureItem()
		}
	}

	override var isSelected: Bool {
		didSet {
			updateSelection()
		}
	}

	override func loadView() {
		view = NSView()
		view.wantsLayer = true
		view.layer?.cornerRadius = 8
		view.layer?.borderWidth = 1

		sourceIconView.translatesAutoresizingMaskIntoConstraints = false
		sourceIconView.imageScaling = .scaleProportionallyUpOrDown
		sourceIconView.image = NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
		view.addSubview(sourceIconView)

		sourceLabel.translatesAutoresizingMaskIntoConstraints = false
		sourceLabel.lineBreakMode = .byTruncatingTail
		sourceLabel.maximumNumberOfLines = 1
		sourceLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
		sourceLabel.textColor = .secondaryLabelColor
		view.addSubview(sourceLabel)

		previewImageView.translatesAutoresizingMaskIntoConstraints = false
		previewImageView.imageScaling = .scaleProportionallyUpOrDown
		previewImageView.wantsLayer = true
		previewImageView.layer?.cornerRadius = 6
		previewImageView.layer?.masksToBounds = true
		view.addSubview(previewImageView)

		label.translatesAutoresizingMaskIntoConstraints = false
		label.lineBreakMode = .byWordWrapping
		label.maximumNumberOfLines = 0
		label.usesSingleLineMode = false
		label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
		label.textColor = .labelColor
		view.addSubview(label)

		let previewHeightConstraint = previewImageView.heightAnchor.constraint(equalToConstant: 72)
		self.previewHeightConstraint = previewHeightConstraint

		NSLayoutConstraint.activate([
			sourceIconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
			sourceIconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
			sourceIconView.widthAnchor.constraint(equalToConstant: 16),
			sourceIconView.heightAnchor.constraint(equalToConstant: 16),
			sourceLabel.leadingAnchor.constraint(equalTo: sourceIconView.trailingAnchor, constant: 6),
			sourceLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
			sourceLabel.centerYAnchor.constraint(equalTo: sourceIconView.centerYAnchor),
			previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
			previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
			previewImageView.topAnchor.constraint(equalTo: sourceIconView.bottomAnchor, constant: 8),
			previewHeightConstraint,
			label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
			label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
			label.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 8),
			label.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -10)
		])

		updateSelection()
	}

	private func configureItem() {
		guard let item else {
			sourceLabel.stringValue = ClipboardHistorySelection.sourceText(for: nil)
			sourceIconView.image = nil
			previewImageView.image = nil
			label.stringValue = ""
			return
		}

		sourceLabel.stringValue = ClipboardHistorySelection.sourceText(for: item.source.appName)
		sourceIconView.image = sourceIcon(for: item.source)

		switch item.content {
		case let .text(text):
			previewImageView.isHidden = true
			previewHeightConstraint?.constant = 0
			previewImageView.image = nil
			label.isHidden = false
			label.stringValue = ClipboardHistorySelection.displayText(for: text)
		case let .image(data):
			previewImageView.isHidden = false
			previewHeightConstraint?.constant = 72
			previewImageView.image = NSImage(data: data)
			label.isHidden = false
			label.stringValue = ClipboardHistorySelection.previewTitle(for: item)
		case let .files(urls):
			previewImageView.isHidden = false
			previewHeightConstraint?.constant = 72
			previewImageView.image = urls.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
			label.isHidden = false
			label.stringValue = ClipboardHistorySelection.previewTitle(for: item)
		}
	}

	private func sourceIcon(for source: ClipboardHistorySource) -> NSImage {
		if let bundleURL = source.bundleURL {
			return NSWorkspace.shared.icon(forFile: bundleURL.path)
		}

		if let bundleIdentifier = source.bundleIdentifier,
		   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
			return NSWorkspace.shared.icon(forFile: url.path)
		}

		return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericApplicationIcon)))
	}

	private func updateSelection() {
		view.layer?.backgroundColor = (
			isSelected
				? NSColor.controlAccentColor.withAlphaComponent(0.22)
				: NSColor.controlBackgroundColor.withAlphaComponent(0.18)
		).cgColor
		view.layer?.borderColor = (
			isSelected
				? NSColor.controlAccentColor
				: NSColor.separatorColor.withAlphaComponent(0.35)
		).cgColor
	}
}
