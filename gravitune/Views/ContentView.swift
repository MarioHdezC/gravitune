//
//  ContentView.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import SwiftUI
import VisualEngine

struct ContentView: View {
    let viewModel: AppViewModel

    var body: some View {
        ZStack {
            if viewModel.display.selectedDisplay != nil {
                RemoteControlSurface(viewModel: viewModel.nowPlaying, isCompact: viewModel.dock.isOpen)
            } else {
                FlowBackground(renderer: viewModel.renderer)
                NowPlayingView(viewModel: viewModel.nowPlaying, isCompact: viewModel.dock.isOpen)
            }
        }
        .overlay {
            BottomDock(viewModel: viewModel.dock) {
                DockPanel(
                    nowPlaying: viewModel.nowPlaying,
                    settings: viewModel.settings,
                    display: viewModel.display
                )
            }
        }
        // Goes after the arrow, whose layer fills the window and would otherwise take the clicks.
        .overlay(alignment: .top) {
            if let display = viewModel.display.selectedDisplay {
                ExternalDisplayBanner(display: display, onReturn: viewModel.display.returnToThisDisplay)
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 480)
        .task {
            await viewModel.run(makeStageView: makeStageView)
        }
    }

    private func makeStageView() -> NSView {
        NSHostingView(rootView: StageView(nowPlaying: viewModel.nowPlaying, renderer: viewModel.renderer))
    }
}

/// Mac window while the visual is on another display, with a static background that uses no GPU.
private struct RemoteControlSurface: View {
    let viewModel: NowPlayingViewModel
    let isCompact: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: viewModel.palette.colors.map(\.color),
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .animation(.easeInOut(duration: 1), value: viewModel.palette)
            NowPlayingView(viewModel: viewModel, isCompact: isCompact)
        }
    }
}

private struct ExternalDisplayBanner: View {
    let display: ExternalDisplay
    let onReturn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label("Showing on \(display.name)", systemImage: "tv")
            Button("Back to This Display", action: onReturn)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 6, y: 1)
        .padding(.top, 44)
    }
}

#Preview {
    ContentView(viewModel: AppViewModel())
}
