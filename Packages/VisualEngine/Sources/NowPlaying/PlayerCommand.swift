//
//  PlayerCommand.swift
//  NowPlaying
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Foundation

public enum RepeatMode: Equatable, Sendable {
    case off
    case all
    case one

    /// Next mode when the button is pressed; Spotify doesn't allow repeating one track by script.
    public func next(for player: MusicPlayer) -> RepeatMode {
        switch (self, player) {
        case (.off, _): .all
        case (.all, .appleMusic): .one
        default: .off
        }
    }
}

public enum PlayerCommand: Equatable, Sendable {
    case togglePlayPause
    case next
    case previous
    case seek(to: TimeInterval)
    case setShuffle(Bool)
    case setRepeat(RepeatMode)
    case setVolume(Int)
}

/// Player state, separate from the track because it changes on every query.
public struct PlaybackDetails: Equatable, Sendable {
    public let isPlaying: Bool
    public let position: TimeInterval
    public let duration: TimeInterval
    public let isShuffling: Bool
    public let repeatMode: RepeatMode
    public let volume: Int
    let capturedAt: Date

    public init(
        isPlaying: Bool,
        position: TimeInterval,
        duration: TimeInterval,
        isShuffling: Bool,
        repeatMode: RepeatMode,
        volume: Int,
        capturedAt: Date = .now
    ) {
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.isShuffling = isShuffling
        self.repeatMode = repeatMode
        self.volume = volume
        self.capturedAt = capturedAt
    }

    /// Estimates the position between queries, which happen every few seconds.
    public func position(at date: Date) -> TimeInterval {
        let elapsed = isPlaying ? date.timeIntervalSince(capturedAt) : 0
        return max(min(position + elapsed, duration), 0)
    }

    /// Anticipates a command's effect so the interface responds instantly.
    func applying(_ command: PlayerCommand, at date: Date) -> PlaybackDetails {
        PlaybackDetails(
            isPlaying: command == .togglePlayPause ? !isPlaying : isPlaying,
            position: {
                if case .seek(let target) = command { return target }
                return position(at: date)
            }(),
            duration: duration,
            isShuffling: {
                if case .setShuffle(let enabled) = command { return enabled }
                return isShuffling
            }(),
            repeatMode: {
                if case .setRepeat(let mode) = command { return mode }
                return repeatMode
            }(),
            volume: {
                if case .setVolume(let level) = command { return level }
                return volume
            }(),
            capturedAt: date
        )
    }
}
