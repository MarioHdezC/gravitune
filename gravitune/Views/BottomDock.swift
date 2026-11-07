//
//  BottomDock.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import SwiftUI
import VisualEngine

extension Animation {
    /// Shared by the dock and the content that makes room for it.
    static let dock = Animation.spring(duration: 0.45, bounce: 0.15)
}

/// Bottom arrow that reacts as the mouse approaches and opens the controls panel.
struct BottomDock<Panel: View>: View {
    let viewModel: DockViewModel
    @ViewBuilder let panel: Panel

    var body: some View {
        VStack(spacing: 12) {
            DockHandle(
                isOpen: viewModel.isOpen,
                proximity: viewModel.handleProximity,
                drift: viewModel.drift,
                restingOpacity: viewModel.restingOpacity,
                bounce: viewModel.introBounce,
                action: viewModel.toggle
            )
            if viewModel.isOpen {
                panel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background {
            if viewModel.isOpen {
                DismissArea(action: viewModel.close)
            }
        }
        .contentShape(.rect)
        .onGeometryChange(for: CGSize.self, of: \.size) { viewModel.containerSize = $0 }
        .onContinuousHover(perform: updatePointer)
        .animation(.dock, value: viewModel.isOpen)
        .task { await viewModel.run() }
    }

    private func updatePointer(_ phase: HoverPhase) {
        switch phase {
        case .active(let location): viewModel.pointerMoved(to: location)
        case .ended: viewModel.pointerExited()
        }
    }
}

/// Invisible layer behind the panel that closes it when clicking outside.
private struct DismissArea: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityHidden(true)
    }
}

private struct DockHandle: View {
    let isOpen: Bool
    let proximity: CGFloat
    let drift: CGFloat
    let restingOpacity: Double
    let bounce: Int
    let action: () -> Void

    private var emphasis: CGFloat { isOpen ? 1 : proximity }
    private var opacity: Double { isOpen ? 1 : max(restingOpacity, proximity) }

    var body: some View {
        Button(action: action) {
            Label(isOpen ? "Hide Controls" : "Show Controls", systemImage: "arrow.up")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce.up, options: .repeat(2), value: bounce)
                .rotationEffect(isOpen ? .degrees(180) : .zero)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .scaleEffect(0.8 + 0.35 * emphasis)
        .offset(x: isOpen ? 0 : drift, y: isOpen ? 0 : -14 * proximity)
        .opacity(opacity)
        .allowsHitTesting(opacity > 0)
        .animation(.interactiveSpring(duration: 0.25), value: proximity)
        .animation(.easeOut(duration: 0.6), value: restingOpacity)
        .animation(.dock, value: isOpen)
    }
}

struct DockPanel: View {
    let nowPlaying: NowPlayingViewModel
    let settings: VisualSettingsViewModel
    let display: DisplayViewModel

    var body: some View {
        VStack(spacing: 14) {
            TransportControls(viewModel: nowPlaying)
            Divider()
            SettingsControls(settings: settings, display: display, palette: nowPlaying.palette)
        }
        .padding(16)
        .frame(maxWidth: 1000)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
        .tint(nowPlaying.palette.accent.color)
        .animation(.easeInOut(duration: 1), value: nowPlaying.palette)
    }
}
