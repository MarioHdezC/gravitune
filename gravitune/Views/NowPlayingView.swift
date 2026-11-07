//
//  NowPlayingView.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import NowPlaying
import SwiftUI

struct NowPlayingView: View {
    let viewModel: NowPlayingViewModel
    let isCompact: Bool

    var body: some View {
        VStack(spacing: 28) {
            CoverView(cover: viewModel.cover)
            PlaybackInfoView(viewModel: viewModel)
        }
        .scaleEffect(isCompact ? 0.72 : 1)
        .offset(y: isCompact ? -130 : 0)
        .animation(.dock, value: isCompact)
    }
}

private struct CoverView: View {
    let cover: Cover?

    var body: some View {
        ZStack {
            if let cover {
                Image(decorative: cover.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 14))
                    .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
                    .id(cover.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .containerRelativeFrame([.horizontal, .vertical]) { length, _ in length * 0.52 }
        .animation(.easeInOut(duration: 1.2), value: cover?.id)
    }
}

/// Shows the current track, or explains why it can't be shown.
private struct PlaybackInfoView: View {
    private static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )

    let viewModel: NowPlayingViewModel

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 6) {
            switch viewModel.status {
            case .active(let track, let isPlaying):
                Text(track.title)
                    .font(.title2.bold())
                Text(viewModel.subtitle(for: track, isPlaying: isPlaying))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
            case .notAuthorized(let player):
                Text("Missing permission to read \(player.title)")
                    .font(.title3.bold())
                Button("Open Automation Settings", action: openAutomationSettings)
            case .idle:
                Text("Play a song to get started")
                    .font(.title3.bold())
            case .noPlayer:
                Text("Open Spotify or Apple Music")
                    .font(.title3.bold())
            }
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .shadow(color: .black.opacity(0.5), radius: 8, y: 2)
        .padding(.horizontal, 40)
    }

    private func openAutomationSettings() {
        if let url = Self.automationSettingsURL {
            openURL(url)
        }
    }
}
