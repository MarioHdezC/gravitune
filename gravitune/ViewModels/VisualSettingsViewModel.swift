//
//  VisualSettingsViewModel.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Observation
import VisualEngine

/// Settings of the visual, applied to the renderer as they change.
@Observable
final class VisualSettingsViewModel {
    private let renderer: FlowRenderer?

    var settings = FlowSettings() {
        didSet { renderer?.settings = settings }
    }

    init(renderer: FlowRenderer?) {
        self.renderer = renderer
    }

    /// Average GPU time per frame. It's not observable: read it on a schedule.
    var gpuMilliseconds: Double { renderer?.gpuMilliseconds ?? 0 }
}
