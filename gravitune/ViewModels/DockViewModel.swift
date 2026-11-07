//
//  DockViewModel.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import AppKit
import Observation

/// State of the bottom dock: whether it's open and how its arrow reacts to the mouse.
@Observable
final class DockViewModel {
    private static let detectionRadius: CGFloat = 320
    private static let handleOffsetFromBottom: CGFloat = 38
    private static let proximityStep: CGFloat = 0.02
    private static let driftFactor: CGFloat = 0.08
    private static let awakeOpacity = 0.35
    private static let introBounceDelay: Duration = .milliseconds(600)
    private static let introDuration: Duration = .seconds(4)
    private static let idleDelay: Duration = .seconds(3)
    private static let idleCheckInterval: Duration = .milliseconds(500)

    var isOpen = false {
        didSet {
            if isOpen { wake() }
        }
    }

    private(set) var drift: CGFloat = 0
    private(set) var introBounce = 0
    private var proximity: CGFloat = 0
    private var isIntroVisible = true
    private var isIdle = false

    // Not observable, so each mouse movement doesn't trigger a redraw.
    @ObservationIgnored var containerSize = CGSize.zero
    @ObservationIgnored private var lastLocation: CGPoint?
    @ObservationIgnored private var lastMovement: ContinuousClock.Instant
    @ObservationIgnored private var isPointerInside = false

    private let setCursorHidden: (Bool) -> Void
    private let isAppActive: () -> Bool

    init(
        now: ContinuousClock.Instant = .now,
        setCursorHidden: @escaping (Bool) -> Void = { NSCursor.setHiddenUntilMouseMoves($0) },
        isAppActive: @escaping () -> Bool = { NSApp.isActive }
    ) {
        lastMovement = now
        self.setCursorHidden = setCursorHidden
        self.isAppActive = isAppActive
    }

    /// How close the mouse is to the arrow, from 0 to 1.
    var handleProximity: CGFloat { isIdle ? 0 : proximity }

    /// Opacity of the closed arrow while the mouse is away.
    var restingOpacity: Double {
        if isIntroVisible { return 1 }
        return isIdle ? 0 : Self.awakeOpacity
    }

    /// Plays the intro and watches for inactivity until the task is cancelled.
    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.playIntro() }
            group.addTask { await self.watchForIdle() }
        }
    }

    func toggle() {
        isOpen.toggle()
    }

    func close() {
        isOpen = false
    }

    func pointerMoved(to location: CGPoint, at now: ContinuousClock.Instant = .now) {
        isPointerInside = true
        // SwiftUI also reports when the view is recomposed: it only counts if the mouse has moved.
        guard location != lastLocation else { return }
        lastLocation = location
        lastMovement = now
        if isIdle { isIdle = false }

        let anchor = CGPoint(x: containerSize.width / 2, y: containerSize.height - Self.handleOffsetFromBottom)
        let horizontal = location.x - anchor.x
        let distance = hypot(horizontal, location.y - anchor.y)
        let closeness = max(1 - distance / Self.detectionRadius, 0)

        // Rounded so that each pixel of mouse movement doesn't trigger a redraw.
        let rounded = (closeness / Self.proximityStep).rounded() * Self.proximityStep
        if rounded != proximity {
            proximity = rounded
            drift = horizontal * Self.driftFactor * rounded
        }
    }

    func pointerExited() {
        isPointerInside = false
        lastLocation = nil
        proximity = 0
        drift = 0
    }

    func checkForIdle(at now: ContinuousClock.Instant = .now) {
        guard !isIdle, !isOpen, now - lastMovement >= Self.idleDelay else { return }
        isIdle = true
        if isPointerInside, isAppActive() {
            setCursorHidden(true)
        }
    }

    private func playIntro() async {
        try? await Task.sleep(for: Self.introBounceDelay)
        introBounce += 1
        try? await Task.sleep(for: Self.introDuration - Self.introBounceDelay)
        isIntroVisible = false
    }

    /// Polling is enough: a timer restarted on every movement would cost more.
    private func watchForIdle() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.idleCheckInterval)
            checkForIdle()
        }
    }

    private func wake() {
        lastMovement = .now
        isIdle = false
        setCursorHidden(false)
    }
}
