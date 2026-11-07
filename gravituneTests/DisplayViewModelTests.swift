//
//  DisplayViewModelTests.swift
//  gravituneTests
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Testing
@testable import gravitune

struct DisplayViewModelTests {
    private static let television = ExternalDisplay(id: 7, name: "TV")

    private let router = FakeDisplayRouter()
    private let viewModel: DisplayViewModel

    init() {
        viewModel = DisplayViewModel(router: router)
    }

    @Test func reportsWhenThereAreNoDisplays() {
        #expect(viewModel.availability == .noExternalDisplays)
    }

    @Test func listsTheAvailableDisplays() {
        router.availableDisplays = [Self.television]
        #expect(viewModel.availability == .available([Self.television]))
    }

    @Test func mirroringTakesPriorityOverTheDisplays() {
        router.availableDisplays = [Self.television]
        router.isMirroring = true
        #expect(viewModel.availability == .mirroring)
    }

    @Test func selectingADisplayReachesTheRouter() {
        router.availableDisplays = [Self.television]

        viewModel.selectedDisplayID = Self.television.id

        #expect(router.selectedDisplayID == Self.television.id)
        #expect(viewModel.selectedDisplay == Self.television)
    }

    @Test func aSelectionThatDisappearedIsNotReported() {
        router.selectedDisplayID = Self.television.id
        #expect(viewModel.selectedDisplay == nil)
    }

    @Test func returningClearsTheSelection() {
        router.availableDisplays = [Self.television]
        router.selectedDisplayID = Self.television.id

        viewModel.returnToThisDisplay()

        #expect(viewModel.selectedDisplay == nil)
        #expect(router.selectedDisplayID == nil)
    }
}
