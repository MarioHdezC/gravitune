//
//  PlayerClient.swift
//  NowPlaying
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import AppKit
import Foundation

enum PlayerClientError: Error, Equatable {
    case notAuthorized
    case notRunning
    case failed(code: Int)
}

protocol PlayerClient: Sendable {
    func isRunning(_ player: MusicPlayer) -> Bool
    func snapshot(of player: MusicPlayer) async throws -> PlayerSnapshot
    func embeddedArtwork(of player: MusicPlayer) async -> Data?
    func perform(_ command: PlayerCommand, on player: MusicPlayer) async throws
}

/// Queries the players with Apple Events.
///
/// Scripts use raw codes instead of each app's terminology: that way they compile
/// without reading its dictionary, which avoids launching it and works inside the sandbox.
final class AppleScriptPlayerClient: PlayerClient, @unchecked Sendable {
    private static let notAuthorizedCode = -1743
    private static let notRunningCodes = [-600, -609]
    private static let playingCode: OSType = 0x6B505350 // kPSP
    private static let pausedCode: OSType = 0x6B505370 // kPSp
    private static let repeatOneCode: OSType = 0x6B527031 // kRp1
    private static let repeatAllCode: OSType = 0x6B416C6C // kAll
    private static let missingValueType: DescType = 0x6D736E67 // msng
    private static let spotifyDurationsPerSecond = 1000.0

    // NSAppleScript doesn't support concurrent execution: this queue guards all of its use.
    private let queue = DispatchQueue(label: "com.mariohernandez.gravitune.apple-events")

    func isRunning(_ player: MusicPlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    func snapshot(of player: MusicPlayer) async throws -> PlayerSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    Self.parse(try Self.run(Self.snapshotSource(for: player)), player: player, at: .now)
                })
            }
        }
    }

    func embeddedArtwork(of player: MusicPlayer) async -> Data? {
        guard player == .appleMusic else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let data = (try? Self.run(Self.embeddedArtworkSource))?.data
                continuation.resume(returning: data?.isEmpty == false ? data : nil)
            }
        }
    }

    func perform(_ command: PlayerCommand, on player: MusicPlayer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                continuation.resume(with: Result {
                    _ = try Self.run(Self.commandSource(command, for: player))
                })
            }
        }
    }

    // MARK: - Scripts

    /// Returns `{state}` if there's no track. If there is one, it adds, in this order:
    /// id, title, artist, album, artwork, position, duration, shuffle, repeat and volume.
    static func snapshotSource(for player: MusicPlayer) -> String {
        let identifier: String
        let artwork: String
        let shuffle: String
        let repeatMode: String
        switch player {
        case .spotify:
            identifier = "«property ID  »"
            artwork = "«property aUrl»"
            shuffle = "«property pShu»"
            repeatMode = "«property pRep»"
        case .appleMusic:
            identifier = "«property pPIS»"
            artwork = "\"\""
            shuffle = "«property pShE»"
            repeatMode = "«property pRpt»"
        }
        return """
        tell application id "\(player.bundleIdentifier)"
            set playerState to «property pPlS»
            set {playerPosition, shuffleValue, repeatValue, volumeValue} to {missing value, missing value, missing value, missing value}
            try
                set shuffleValue to \(shuffle)
                set repeatValue to \(repeatMode)
                set volumeValue to «property pVol»
                set playerPosition to «property pPos»
            end try
            try
                tell «property pTrk»
                    return {playerState, \(identifier), «property pnam», «property pArt», «property pAlb», \(artwork), playerPosition, «property pDur», shuffleValue, repeatValue, volumeValue}
                end tell
            on error
                return {playerState}
            end try
        end tell
        """
    }

    static let embeddedArtworkSource = """
    tell application id "com.apple.Music"
        tell «property pTrk»
            if (count «class cArt») is 0 then return missing value
            return «property pRaw» of «class cArt» 1
        end tell
    end tell
    """

    static func commandSource(_ command: PlayerCommand, for player: MusicPlayer) -> String {
        let isSpotify = player == .spotify
        let statement: String
        switch command {
        case .togglePlayPause:
            statement = isSpotify ? "«event spfyPlPs»" : "«event hookPlPs»"
        case .next:
            statement = isSpotify ? "«event spfyNext»" : "«event hookNext»"
        case .previous:
            statement = isSpotify ? "«event spfyPrev»" : "«event hookBack»"
        case .seek(let position):
            statement = "set «property pPos» to \(position)"
        case .setShuffle(let isEnabled):
            statement = "set \(isSpotify ? "«property pShu»" : "«property pShE»") to \(isEnabled)"
        case .setRepeat(let mode):
            if isSpotify {
                statement = "set «property pRep» to \(mode != .off)"
            } else {
                statement = "set «property pRpt» to «constant ****\(appleMusicCode(for: mode))»"
            }
        case .setVolume(let level):
            statement = "set «property pVol» to \(level)"
        }
        return """
        tell application id "\(player.bundleIdentifier)"
            \(statement)
        end tell
        """
    }

    private static func appleMusicCode(for mode: RepeatMode) -> String {
        switch mode {
        case .off: "kRpO"
        case .all: "kAll"
        case .one: "kRp1"
        }
    }

    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else { throw PlayerClientError.failed(code: 0) }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let code = errorInfo?[NSAppleScript.errorNumber] as? Int {
            if code == notAuthorizedCode { throw PlayerClientError.notAuthorized }
            if notRunningCodes.contains(code) { throw PlayerClientError.notRunning }
            throw PlayerClientError.failed(code: code)
        }
        return result
    }

    // MARK: - Reading the Result

    static func parse(_ descriptor: NSAppleEventDescriptor, player: MusicPlayer, at date: Date) -> PlayerSnapshot {
        let state = state(from: descriptor.atIndex(1))
        guard state != .stopped,
              descriptor.numberOfItems >= 5,
              let id = text(descriptor, 2), !id.isEmpty else {
            return PlayerSnapshot(player: player, state: state, track: nil)
        }
        let track = NowPlayingTrack(
            player: player,
            id: id,
            title: text(descriptor, 3) ?? "",
            artist: text(descriptor, 4) ?? "",
            album: text(descriptor, 5) ?? "",
            artworkURL: secureURL(from: text(descriptor, 6))
        )
        return PlayerSnapshot(
            player: player,
            state: state,
            track: track,
            details: details(from: descriptor, player: player, state: state, date: date)
        )
    }

    private static func details(
        from descriptor: NSAppleEventDescriptor,
        player: MusicPlayer,
        state: PlaybackState,
        date: Date
    ) -> PlaybackDetails {
        // Spotify documents the duration in seconds, but delivers it in milliseconds.
        let divisor = player == .spotify ? spotifyDurationsPerSecond : 1
        return PlaybackDetails(
            isPlaying: state == .playing,
            position: number(descriptor, 7) ?? 0,
            duration: (number(descriptor, 8) ?? 0) / divisor,
            isShuffling: value(descriptor, 9)?.booleanValue ?? false,
            repeatMode: repeatMode(from: value(descriptor, 10), player: player),
            volume: Int(number(descriptor, 11) ?? 0),
            capturedAt: date
        )
    }

    private static func repeatMode(from descriptor: NSAppleEventDescriptor?, player: MusicPlayer) -> RepeatMode {
        guard let descriptor else { return .off }
        switch player {
        case .spotify:
            return descriptor.booleanValue ? .all : .off
        case .appleMusic:
            switch descriptor.enumCodeValue {
            case repeatOneCode: return .one
            case repeatAllCode: return .all
            default: return .off
            }
        }
    }

    private static func value(_ descriptor: NSAppleEventDescriptor, _ index: Int) -> NSAppleEventDescriptor? {
        guard index <= descriptor.numberOfItems,
              let item = descriptor.atIndex(index),
              item.descriptorType != missingValueType else { return nil }
        return item
    }

    private static func number(_ descriptor: NSAppleEventDescriptor, _ index: Int) -> Double? {
        value(descriptor, index)?.doubleValue
    }

    private static func state(from descriptor: NSAppleEventDescriptor?) -> PlaybackState {
        switch descriptor?.enumCodeValue {
        case playingCode: .playing
        case pausedCode: .paused
        default: .stopped
        }
    }

    private static func text(_ descriptor: NSAppleEventDescriptor, _ index: Int) -> String? {
        value(descriptor, index)?.stringValue
    }

    /// Spotify can return `http` links, which App Transport Security would block.
    private static func secureURL(from text: String?) -> URL? {
        guard let text, !text.isEmpty, var components = URLComponents(string: text) else { return nil }
        components.scheme = "https"
        return components.url
    }
}
