import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

private final class RenameNotificationFlag {
    var wasPosted = false

    func markPosted() {
        wasPosted = true
    }
}

/// Regression coverage for the reported bug that ⌘⇧R does not rename the focused
/// workspace. Verifies (1) the default bindings are distinct (⌘R renames the tab,
/// ⌘⇧R renames the workspace), and (2) each binding dispatches to the matching
/// command-palette request while never posting the other.
@MainActor
@Suite(.serialized)
struct AppDelegateRenameWorkspaceShortcutRegressionTests {
    @Test func defaultBindingsAreDistinct() {
        try? withIsolatedShortcutSettings {
            let renameTab = KeyboardShortcutSettings.shortcut(for: .renameTab)
            let renameWorkspace = KeyboardShortcutSettings.shortcut(for: .renameWorkspace)

            #expect(renameTab.key.lowercased() == "r")
            #expect(renameTab.command && !renameTab.shift)

            #expect(renameWorkspace.key.lowercased() == "r")
            #expect(renameWorkspace.command && renameWorkspace.shift)

            #expect(renameTab != renameWorkspace)
        }
    }

    @Test func cmdRRequestsRenameTabNotRenameWorkspace() throws {
        try withIsolatedShortcutSettings {
            let appDelegate = try #require(AppDelegate.shared)
            let windowId = appDelegate.createMainWindow()
            defer { closeWindow(withId: windowId) }
            let window = try #require(mainWindow(withId: windowId))

            let tabPosted = RenameNotificationFlag()
            let tabToken = NotificationCenter.default.addObserver(
                forName: .commandPaletteRenameTabRequested,
                object: nil,
                queue: nil
            ) { _ in tabPosted.markPosted() }
            defer { NotificationCenter.default.removeObserver(tabToken) }

            let workspacePosted = RenameNotificationFlag()
            let workspaceToken = NotificationCenter.default.addObserver(
                forName: .commandPaletteRenameWorkspaceRequested,
                object: nil,
                queue: nil
            ) { _ in workspacePosted.markPosted() }
            defer { NotificationCenter.default.removeObserver(workspaceToken) }

            let cmdR = try #require(makeKeyDownEvent(
                key: "r",
                modifiers: [.command],
                keyCode: 15,
                windowNumber: window.windowNumber
            ))

#if DEBUG
            #expect(appDelegate.debugHandleCustomShortcut(event: cmdR))
#else
            Issue.record("debugHandleCustomShortcut is only available in DEBUG")
#endif

            #expect(tabPosted.wasPosted)
            #expect(!workspacePosted.wasPosted)
        }
    }

    @Test func cmdShiftRRequestsRenameWorkspaceNotRenameTab() throws {
        try withIsolatedShortcutSettings {
            let appDelegate = try #require(AppDelegate.shared)
            let windowId = appDelegate.createMainWindow()
            defer { closeWindow(withId: windowId) }
            let window = try #require(mainWindow(withId: windowId))

            let workspacePosted = RenameNotificationFlag()
            let workspaceToken = NotificationCenter.default.addObserver(
                forName: .commandPaletteRenameWorkspaceRequested,
                object: nil,
                queue: nil
            ) { _ in workspacePosted.markPosted() }
            defer { NotificationCenter.default.removeObserver(workspaceToken) }

            let tabPosted = RenameNotificationFlag()
            let tabToken = NotificationCenter.default.addObserver(
                forName: .commandPaletteRenameTabRequested,
                object: nil,
                queue: nil
            ) { _ in tabPosted.markPosted() }
            defer { NotificationCenter.default.removeObserver(tabToken) }

            let cmdShiftR = try #require(makeKeyDownEvent(
                key: "r",
                modifiers: [.command, .shift],
                keyCode: 15,
                windowNumber: window.windowNumber
            ))

#if DEBUG
            #expect(appDelegate.debugHandleCustomShortcut(event: cmdShiftR))
#else
            Issue.record("debugHandleCustomShortcut is only available in DEBUG")
#endif

            #expect(workspacePosted.wasPosted)
            #expect(!tabPosted.wasPosted)
        }
    }

    private func withIsolatedShortcutSettings(_ body: () throws -> Void) rethrows {
        let actionsWithPersistedShortcut = Set(
            KeyboardShortcutSettings.Action.allCases.filter {
                UserDefaults.standard.object(forKey: $0.defaultsKey) != nil
            }
        )
        let savedShortcutsByAction = Dictionary(
            uniqueKeysWithValues: actionsWithPersistedShortcut.map { action in
                (action, KeyboardShortcutSettings.shortcut(for: action))
            }
        )
        let originalSettingsFileStore = KeyboardShortcutSettings.installIsolatedTestFileStore(
            prefix: "cmux-rename-workspace-shortcut-regression"
        )
        KeyboardShortcutSettings.resetAll()
        defer {
            KeyboardShortcutSettings.settingsFileStore = originalSettingsFileStore
            for action in KeyboardShortcutSettings.Action.allCases {
                if actionsWithPersistedShortcut.contains(action),
                   let savedShortcut = savedShortcutsByAction[action] {
                    KeyboardShortcutSettings.setShortcut(savedShortcut, for: action)
                } else {
                    KeyboardShortcutSettings.resetShortcut(for: action)
                }
            }
        }
        try body()
    }

    private func makeKeyDownEvent(
        key: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: UInt16,
        windowNumber: Int
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: windowNumber,
            context: nil,
            characters: key,
            charactersIgnoringModifiers: key,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    private func mainWindow(withId windowId: UUID) -> NSWindow? {
        let identifier = "cmux.main.\(windowId.uuidString)"
        return NSApp.windows.first(where: { $0.identifier?.rawValue == identifier })
    }

    private func closeWindow(withId windowId: UUID) {
        guard let window = mainWindow(withId: windowId) else { return }
        window.performClose(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}
