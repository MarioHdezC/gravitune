//
//  DockViewModelTests.swift
//  gravituneTests
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Foundation
import Testing
@testable import Gravitune

struct DockViewModelTests {
    private static let handle = CGPoint(x: 500, y: 762)
    private static let start = ContinuousClock.now

    private final class Cursor {
        var hiddenStates: [Bool] = []
    }

    private let cursor = Cursor()

    private func makeViewModel(isAppActive: Bool = true) -> DockViewModel {
        let cursor = cursor
        let viewModel = DockViewModel(
            now: Self.start,
            setCursorHidden: { cursor.hiddenStates.append($0) },
            isAppActive: { isAppActive }
        )
        viewModel.containerSize = CGSize(width: 1000, height: 800)
        return viewModel
    }

    @Test func proximityIsFullOverTheHandle() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: Self.handle, at: Self.start)
        #expect(viewModel.handleProximity == 1)
    }

    @Test func proximityIsZeroOutsideTheDetectionRadius() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: CGPoint(x: 0, y: 0), at: Self.start)
        #expect(viewModel.handleProximity == 0)
    }

    @Test func handleDriftsTowardsTheMouse() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: CGPoint(x: 600, y: 762), at: Self.start)
        #expect(viewModel.drift > 0)

        viewModel.pointerMoved(to: CGPoint(x: 350, y: 762), at: Self.start)
        #expect(viewModel.drift < 0)
    }

    @Test func leavingTheWindowResetsTheHandle() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: CGPoint(x: 600, y: 762), at: Self.start)

        viewModel.pointerExited()

        #expect(viewModel.handleProximity == 0)
        #expect(viewModel.drift == 0)
    }

    @Test func staysAwakeBeforeTheIdleDelay() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: Self.handle, at: Self.start)

        viewModel.checkForIdle(at: Self.start + .seconds(2))

        #expect(viewModel.handleProximity == 1)
        #expect(cursor.hiddenStates.isEmpty)
    }

    @Test func goesIdleAndHidesTheCursorAfterTheDelay() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: Self.handle, at: Self.start)

        viewModel.checkForIdle(at: Self.start + .seconds(3))

        #expect(viewModel.handleProximity == 0)
        #expect(cursor.hiddenStates == [true])
    }

    @Test func movingTheMouseWakesTheHandle() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: CGPoint(x: 499, y: 762), at: Self.start)
        viewModel.checkForIdle(at: Self.start + .seconds(3))

        viewModel.pointerMoved(to: Self.handle, at: Self.start + .seconds(4))

        #expect(viewModel.handleProximity > 0)
    }

    @Test func doesNotHideTheCursorOutsideTheWindowOrInTheBackground() {
        let outside = makeViewModel()
        outside.checkForIdle(at: Self.start + .seconds(3))

        let background = makeViewModel(isAppActive: false)
        background.pointerMoved(to: Self.handle, at: Self.start)
        background.checkForIdle(at: Self.start + .seconds(3))

        #expect(cursor.hiddenStates.isEmpty)
    }

    @Test func doesNotGoIdleWhileOpen() {
        let viewModel = makeViewModel()
        viewModel.pointerMoved(to: Self.handle, at: Self.start)
        viewModel.isOpen = true

        viewModel.checkForIdle(at: .now + .seconds(10))

        #expect(viewModel.handleProximity == 1)
    }

    @Test func openingWakesTheCursor() {
        let viewModel = makeViewModel()
        viewModel.toggle()
        #expect(viewModel.isOpen)
        #expect(cursor.hiddenStates == [false])

        viewModel.close()
        #expect(!viewModel.isOpen)
    }
}
