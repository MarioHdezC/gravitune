//
//  DisplayRouter.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import AppKit
import Observation

/// What the app needs from the object that places the visual on a display.
protocol DisplayRouting: AnyObject, Observable {
    var availableDisplays: [ExternalDisplay] { get }
    var isMirroring: Bool { get }
    var selectedDisplayID: CGDirectDisplayID? { get set }

    /// Follows display changes until the task is cancelled.
    func run(makeStageView: @escaping @MainActor () -> NSView) async
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Decides which display shows the visual and keeps that display's window.
@Observable
final class DisplayRouter: DisplayRouting {
    private static let changeNotifications: [Notification.Name] = [
        NSApplication.didChangeScreenParametersNotification,
        NSWindow.didChangeScreenNotification,
        NSWindow.didBecomeMainNotification
    ]

    /// Available displays, excluding the main window's one.
    private(set) var availableDisplays: [ExternalDisplay] = []

    /// While mirroring, macOS presents all displays as a single one.
    private(set) var isMirroring = false

    /// Selected external display; `nil` shows the visual in the main window.
    var selectedDisplayID: CGDirectDisplayID? {
        didSet { updateStageWindow() }
    }

    @ObservationIgnored private var stageWindow: NSWindow?
    @ObservationIgnored private var makeStageView: (@MainActor () -> NSView)?

    /// Follows display changes until the task is cancelled.
    func run(makeStageView: @escaping @MainActor () -> NSView) async {
        self.makeStageView = makeStageView
        refresh()
        defer { selectedDisplayID = nil }

        await withDiscardingTaskGroup { group in
            for name in Self.changeNotifications {
                group.addTask { await self.refresh(on: name) }
            }
        }
    }

    private func refresh(on name: Notification.Name) async {
        let changes = NotificationCenter.default.notifications(named: name).map { _ in }
        for await _ in changes {
            refresh()
        }
    }

    private func refresh() {
        let hostID = hostWindow?.screen?.displayID
        let displays = NSScreen.screens.compactMap { screen -> ExternalDisplay? in
            guard let id = screen.displayID, id != hostID else { return nil }
            return ExternalDisplay(id: id, name: screen.localizedName)
        }
        if displays != availableDisplays { availableDisplays = displays }

        let mirroring = CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0
        if mirroring != isMirroring { isMirroring = mirroring }

        // If the TV disconnects or the window moves onto it, the visual returns to the Mac.
        if let selectedDisplayID, !displays.contains(where: { $0.id == selectedDisplayID }) {
            self.selectedDisplayID = nil
        } else {
            updateStageWindow()
        }
    }

    private var hostWindow: NSWindow? {
        NSApp.windows.first { $0 !== stageWindow && $0.canBecomeMain && $0.isVisible }
    }

    private func updateStageWindow() {
        guard let selectedDisplayID,
              let screen = NSScreen.screens.first(where: { $0.displayID == selectedDisplayID }),
              let window = stageWindow ?? makeStageWindow() else {
            stageWindow?.close()
            stageWindow = nil
            return
        }
        stageWindow = window
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
    }

    private func makeStageWindow() -> NSWindow? {
        guard let makeStageView else { return nil }
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = makeStageView()
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        // Above that display's menu bar and Dock, without capturing the mouse.
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        return window
    }
}
