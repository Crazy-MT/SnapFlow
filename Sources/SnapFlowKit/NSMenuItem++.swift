import Cocoa

extension NSMenuItem {
	private struct AssociatedKeys {
		static let observer = ObjectAssociation<NSObjectProtocol>()
	}

	// TODO: Make this a getter/setter. We must first add the ability to create a `Shortcut` from a `keyEquivalent`.
	/**
	Show a recorded keyboard shortcut in a `NSMenuItem`.

	The menu item will automatically be kept up to date with changes to the keyboard shortcut.

	Pass in `nil` to clear the keyboard shortcut.

	This method overrides `.keyEquivalent` and `.keyEquivalentModifierMask`.

	```
	import Cocoa
	import SnapFlowKit

	extension SnapFlowKit.Name {
		static let toggleUnicornMode = Self("toggleUnicornMode")
	}

	// … `Recorder` logic for recording the keyboard shortcut …

	let menuItem = NSMenuItem()
	menuItem.title = "Toggle Unicorn Mode"
	menuItem.setShortcut(for: .toggleUnicornMode)
	```

	You can test this method in the example project. Run it, record a shortcut and then look at the “Test” menu in the app's main menu.

	- Important: You will have to disable the global keyboard shortcut while the menu is open, as otherwise, the keyboard events will be buffered up and triggered when the menu closes. This is because `NSMenu` puts the thread in tracking-mode, which prevents the keyboard events from being received. You can listen to whether a menu is open by implementing `NSMenuDelegate#menuWillOpen` and `NSMenuDelegate#menuDidClose`. You then use `SnapFlowKit.disable` and `SnapFlowKit.enable`.
	*/
	public func setShortcut(for name: SnapFlowKit.Name?) {
		func clear() {
			keyEquivalent = ""
			keyEquivalentModifierMask = []
		}

		guard let name = name else {
			clear()
			AssociatedKeys.observer[self] = nil
			return
		}

		func set() {
			guard let shortcut = SnapFlowKit.Shortcut(name: name) else {
				clear()
				return
			}

			keyEquivalent = shortcut.keyEquivalent
			keyEquivalentModifierMask = shortcut.modifiers
		}

		// `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` works on a background thread, but crashes when used in a `NSBackgroundActivityScheduler` task, so we ensure it's not run in that queue.
		if DispatchQueue.isCurrentQueueNSBackgroundActivitySchedulerQueue {
			DispatchQueue.main.async {
				set()
			}
		} else {
			set()
		}

		// TODO: Use Combine when targeting macOS 10.15.
		AssociatedKeys.observer[self] = NotificationCenter.default.addObserver(forName: .shortcutByNameDidChange, object: nil, queue: nil) { notification in
			guard
				let nameInNotification = notification.userInfo?["name"] as? SnapFlowKit.Name,
				nameInNotification == name
			else {
				return
			}

			set()
		}
	}
}
