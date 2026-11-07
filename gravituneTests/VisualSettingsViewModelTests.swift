//
//  VisualSettingsViewModelTests.swift
//  gravituneTests
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Testing
import VisualEngine
@testable import Gravitune

struct VisualSettingsViewModelTests {
    @Test func changesReachTheRenderer() throws {
        let renderer = try #require(FlowRenderer())
        let viewModel = VisualSettingsViewModel(renderer: renderer)

        viewModel.settings.style = .aurora
        viewModel.settings.speed = 0.5

        #expect(renderer.settings == viewModel.settings)
    }

    @Test func worksWithoutARenderer() {
        let viewModel = VisualSettingsViewModel(renderer: nil)
        viewModel.settings.style = .ocean
        #expect(viewModel.gpuMilliseconds == 0)
    }
}
