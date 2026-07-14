import Carbon.HIToolbox

private func carbonSnapFlowKitEventHandler(eventHandlerCall: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
	CarbonSnapFlowKit.handleEvent(event)
}

enum CarbonSnapFlowKit {
	private final class HotKey {
		let shortcut: SnapFlowKit.Shortcut
		let carbonHotKeyId: Int
		let carbonHotKey: EventHotKeyRef
		let onKeyDown: (SnapFlowKit.Shortcut) -> Void
		let onKeyUp: (SnapFlowKit.Shortcut) -> Void

		init(
			shortcut: SnapFlowKit.Shortcut,
			carbonHotKeyID: Int,
			carbonHotKey: EventHotKeyRef,
			onKeyDown: @escaping (SnapFlowKit.Shortcut) -> Void,
			onKeyUp: @escaping (SnapFlowKit.Shortcut) -> Void
		) {
			self.shortcut = shortcut
			self.carbonHotKeyId = carbonHotKeyID
			self.carbonHotKey = carbonHotKey
			self.onKeyDown = onKeyDown
			self.onKeyUp = onKeyUp
		}
	}

	private static var hotKeys = [Int: HotKey]()

	// `SSKS` is just short for `Sindre Sorhus Keyboard Shortcuts`.
	private static let hotKeySignature = UTGetOSTypeFromString("SSKS" as CFString)

	private static var hotKeyId = 0
	private static var eventHandler: EventHandlerRef?

	private static func setUpEventHandlerIfNeeded() {
		guard
			eventHandler == nil,
			let dispatcher = GetEventDispatcherTarget()
		else {
			return
		}

		let eventSpecs = [
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
			EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
		]

		InstallEventHandler(
			dispatcher,
			carbonSnapFlowKitEventHandler,
			eventSpecs.count,
			eventSpecs,
			nil,
			&eventHandler
		)
	}

	static func register(
		_ shortcut: SnapFlowKit.Shortcut,
		onKeyDown: @escaping (SnapFlowKit.Shortcut) -> Void,
		onKeyUp: @escaping (SnapFlowKit.Shortcut) -> Void
	) {
		hotKeyId += 1

		var eventHotKey: EventHotKeyRef?
		let registerError = RegisterEventHotKey(
			UInt32(shortcut.carbonKeyCode),
			UInt32(shortcut.carbonModifiers),
			EventHotKeyID(signature: hotKeySignature, id: UInt32(hotKeyId)),
			GetEventDispatcherTarget(),
			0,
			&eventHotKey
		)

		guard
			registerError == noErr,
			let carbonHotKey = eventHotKey
		else {
			return
		}

		hotKeys[hotKeyId] = HotKey(
			shortcut: shortcut,
			carbonHotKeyID: hotKeyId,
			carbonHotKey: carbonHotKey,
			onKeyDown: onKeyDown,
			onKeyUp: onKeyUp
		)

		setUpEventHandlerIfNeeded()
	}

	private static func unregisterHotKey(_ hotKey: HotKey) {
		UnregisterEventHotKey(hotKey.carbonHotKey)
		hotKeys.removeValue(forKey: hotKey.carbonHotKeyId)
	}

	static func unregister(_ shortcut: SnapFlowKit.Shortcut) {
		for hotKey in hotKeys.values where hotKey.shortcut == shortcut {
			unregisterHotKey(hotKey)
		}
	}

	static func unregisterAll() {
		for hotKey in hotKeys.values {
			unregisterHotKey(hotKey)
		}
	}

	fileprivate static func handleEvent(_ event: EventRef?) -> OSStatus {
		guard let event = event else {
			return OSStatus(eventNotHandledErr)
		}

		var eventHotKeyId = EventHotKeyID()
		let error = GetEventParameter(
			event,
			UInt32(kEventParamDirectObject),
			UInt32(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&eventHotKeyId
		)

		guard error == noErr else {
			return error
		}

		guard
			eventHotKeyId.signature == hotKeySignature,
			let hotKey = hotKeys[Int(eventHotKeyId.id)]
		else {
			return OSStatus(eventNotHandledErr)
		}

		switch Int(GetEventKind(event)) {
		case kEventHotKeyPressed:
			hotKey.onKeyDown(hotKey.shortcut)
			return noErr
		case kEventHotKeyReleased:
			hotKey.onKeyUp(hotKey.shortcut)
			return noErr
		default:
			break
		}

		return OSStatus(eventNotHandledErr)
	}
}

extension CarbonSnapFlowKit {
	static var system: [SnapFlowKit.Shortcut] {
		var shortcutsUnmanaged: Unmanaged<CFArray>?
		guard
			CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
			let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
		else {
			assertionFailure("Could not get system keyboard shortcuts")
			return []
		}

		return shortcuts.compactMap {
			guard
				($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
				let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
				let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
			else {
				return nil
			}

			return SnapFlowKit.Shortcut(
				carbonKeyCode: carbonKeyCode,
				carbonModifiers: carbonModifiers
			)
		}
	}
}
