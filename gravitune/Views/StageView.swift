//
//  StageView.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import SwiftUI
import VisualEngine

/// What an external display shows: only the visual, with no controls.
struct StageView: View {
    let nowPlaying: NowPlayingViewModel
    let renderer: FlowRenderer?

    var body: some View {
        ZStack {
            FlowBackground(renderer: renderer, presentation: .composited)
            NowPlayingView(viewModel: nowPlaying, isCompact: false)
        }
        .ignoresSafeArea()
    }
}
