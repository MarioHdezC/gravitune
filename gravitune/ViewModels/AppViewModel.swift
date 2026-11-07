//
//  AppViewModel.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import AppKit
import Observation
import VisualEngine

/// Composes the feature view models and runs everything that lives as long as the app.
@Observable
final class AppViewModel {
    let renderer: FlowRenderer?
    let nowPlaying: NowPlayingViewModel
    let dock: DockViewModel
    let settings: VisualSettingsViewModel
    let display: DisplayViewModel

    private let sleepBlocker = DisplaySleepBlocker()

    init() {
        let renderer = FlowRenderer()
        self.renderer = renderer
        nowPlaying = NowPlayingViewModel(renderer: renderer)
        dock = DockViewModel()
        settings = VisualSettingsViewModel(renderer: renderer)
        display = DisplayViewModel()
    }

    /// Runs the app's background work until the task is cancelled.
    func run(makeStageView: @escaping @MainActor () -> NSView) async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.nowPlaying.run() }
            group.addTask { await self.display.run(makeStageView: makeStageView) }
            group.addTask { await self.keepDisplayAwakeWhileMusicPlays() }
        }
    }

    private func keepDisplayAwakeWhileMusicPlays() async {
        for await isPlaying in Observations({ self.nowPlaying.isMusicPlaying }) {
            sleepBlocker.setActive(isPlaying)
        }
    }
}
