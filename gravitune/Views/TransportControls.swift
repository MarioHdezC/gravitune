//
//  TransportControls.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import NowPlaying
import SwiftUI

/// Player controls for the track that is playing.
struct TransportControls: View {
    let viewModel: NowPlayingViewModel

    var body: some View {
        VStack(spacing: 10) {
            ProgressRow(details: viewModel.playback, onSeek: viewModel.seek(to:))

            HStack {
                Spacer()
                    .frame(maxWidth: .infinity)

                HStack(spacing: 24) {
                    TransportButton(
                        title: "Shuffle",
                        systemImage: "shuffle",
                        isActive: viewModel.isShuffling,
                        action: viewModel.toggleShuffle
                    )
                    TransportButton(title: "Previous", systemImage: "backward.fill", action: viewModel.skipToPrevious)
                    TransportButton(
                        title: viewModel.isPlaying ? "Pause" : "Play",
                        systemImage: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                        font: .largeTitle,
                        action: viewModel.togglePlayPause
                    )
                    TransportButton(title: "Next", systemImage: "forward.fill", action: viewModel.skipToNext)
                    TransportButton(
                        title: "Repeat",
                        systemImage: viewModel.repeatMode == .one ? "repeat.1" : "repeat",
                        isActive: viewModel.repeatMode != .off,
                        action: viewModel.cycleRepeatMode
                    )
                }

                VolumeControl(volume: viewModel.volume, onChange: viewModel.setVolume)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .disabled(!viewModel.areControlsEnabled)
    }
}

private struct TransportButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var font = Font.title3
    var isActive: Bool?
    let action: () -> Void

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(font)
            .foregroundStyle(tint)
    }

    private var tint: AnyShapeStyle {
        switch isActive {
        case true?: AnyShapeStyle(.tint)
        case false?: AnyShapeStyle(.secondary)
        case nil: AnyShapeStyle(.primary)
        }
    }
}

private struct ProgressRow: View {
    let details: PlaybackDetails?
    let onSeek: (TimeInterval) -> Void

    @State private var scrubPosition: TimeInterval?

    private var duration: TimeInterval { details?.duration ?? 0 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = scrubPosition ?? details?.position(at: context.date) ?? 0
            HStack(spacing: 10) {
                TimeLabel(seconds: position)
                Slider(
                    value: Binding(get: { position }, set: { scrubPosition = $0 }),
                    in: 0...max(duration, 1),
                    onEditingChanged: finishScrubbing
                )
                .labelsHidden()
                .disabled(duration == 0)
                TimeLabel(seconds: duration)
            }
        }
        .controlSize(.small)
    }

    private func finishScrubbing(isEditing: Bool) {
        guard !isEditing, let scrubPosition else { return }
        onSeek(scrubPosition)
        self.scrubPosition = nil
    }
}

private struct TimeLabel: View {
    let seconds: TimeInterval

    var body: some View {
        Text(Duration.seconds(seconds), format: .time(pattern: .minuteSecond))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 44)
    }
}

private struct VolumeControl: View {
    let volume: Int
    let onChange: (Int) -> Void

    @State private var draft: Double?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: Binding(get: { draft ?? Double(volume) }, set: { draft = $0 }),
                in: 0...100,
                onEditingChanged: finishEditing
            )
            .labelsHidden()
            .accessibilityLabel("Volume")
            .frame(maxWidth: 130)
        }
        .controlSize(.small)
    }

    private func finishEditing(isEditing: Bool) {
        guard !isEditing, let draft else { return }
        onChange(Int(draft))
        self.draft = nil
    }
}
