//
//  AppleScriptPlayerClientTests.swift
//  NowPlayingTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import AppKit
import Testing
@testable import NowPlaying

struct AppleScriptPlayerClientTests {
    private static let playing: OSType = 0x6B505350
    private static let paused: OSType = 0x6B505370
    private static let stopped: OSType = 0x6B505353

    @Test(arguments: MusicPlayer.allCases)
    func scriptsCompileWithoutThePlayer(player: MusicPlayer) throws {
        guard isInstalled(player) else { return }
        let script = try #require(NSAppleScript(source: AppleScriptPlayerClient.snapshotSource(for: player)))
        var error: NSDictionary?

        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
    }

    @Test func artworkScriptCompilesWithoutThePlayer() throws {
        let script = try #require(NSAppleScript(source: AppleScriptPlayerClient.embeddedArtworkSource))
        var error: NSDictionary?

        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
    }

    @Test(arguments: MusicPlayer.allCases, [
        PlayerCommand.togglePlayPause, .next, .previous, .seek(to: 12.5), .setShuffle(true),
        .setRepeat(.off), .setRepeat(.all), .setRepeat(.one), .setVolume(40)
    ])
    func commandsCompileWithoutThePlayer(player: MusicPlayer, command: PlayerCommand) throws {
        guard isInstalled(player) else { return }
        let script = try #require(NSAppleScript(source: AppleScriptPlayerClient.commandSource(command, for: player)))
        var error: NSDictionary?

        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
    }

    @Test func spotifyDurationArrivesInMilliseconds() throws {
        let result = list(Self.playing, "id", "Song", "Artist", "Album", "")
        result.insert(NSAppleEventDescriptor(double: 42.5), at: 7)
        result.insert(NSAppleEventDescriptor(int32: 180_000), at: 8)
        result.insert(NSAppleEventDescriptor(boolean: true), at: 9)
        result.insert(NSAppleEventDescriptor(boolean: true), at: 10)
        result.insert(NSAppleEventDescriptor(int32: 70), at: 11)

        let details = try #require(AppleScriptPlayerClient.parse(result, player: .spotify, at: .now).details)

        #expect(details.position == 42.5)
        #expect(details.duration == 180)
        #expect(details.isShuffling)
        #expect(details.repeatMode == .all)
        #expect(details.volume == 70)
    }

    @Test func appleMusicRepeatOneAndSecondsAreRead() throws {
        let result = list(Self.paused, "id", "Song", "Artist", "Album", "")
        result.insert(NSAppleEventDescriptor(double: 3), at: 7)
        result.insert(NSAppleEventDescriptor(double: 200.5), at: 8)
        result.insert(NSAppleEventDescriptor(boolean: false), at: 9)
        result.insert(NSAppleEventDescriptor(enumCode: 0x6B527031), at: 10)
        result.insert(NSAppleEventDescriptor(int32: 55), at: 11)

        let details = try #require(AppleScriptPlayerClient.parse(result, player: .appleMusic, at: .now).details)

        #expect(details.duration == 200.5)
        #expect(details.repeatMode == .one)
        #expect(!details.isPlaying)
    }

    @Test func missingValuesFallBackToZero() throws {
        let result = list(Self.playing, "id", "Radio", "", "", "")
        for index in 7...11 {
            result.insert(NSAppleEventDescriptor(descriptorType: 0x6D736E67, data: nil) ?? .null(), at: index)
        }

        let details = try #require(AppleScriptPlayerClient.parse(result, player: .appleMusic, at: .now).details)

        #expect(details.position == 0)
        #expect(details.duration == 0)
        #expect(details.repeatMode == .off)
    }

    @Test func parsesASpotifyTrackAndSecuresItsArtworkLink() throws {
        let result = list(Self.playing, "spotify:track:1", "Song", "Artist", "Album", "http://i.scdn.co/image/abc")

        let snapshot = AppleScriptPlayerClient.parse(result, player: .spotify, at: .now)

        #expect(snapshot.state == .playing)
        let track = try #require(snapshot.track)
        #expect(track.id == "spotify:track:1")
        #expect(track.title == "Song")
        #expect(track.artworkURL?.absoluteString == "https://i.scdn.co/image/abc")
    }

    @Test func parsesAnAppleMusicTrackWithoutArtworkLink() throws {
        let result = list(Self.paused, "ABC123", "Song", "Artist", "Album", "")

        let snapshot = AppleScriptPlayerClient.parse(result, player: .appleMusic, at: .now)

        #expect(snapshot.state == .paused)
        #expect(try #require(snapshot.track).artworkURL == nil)
    }

    @Test func playerWithoutTrackHasNoTrack() {
        let snapshot = AppleScriptPlayerClient.parse(list(Self.stopped), player: .spotify, at: .now)

        #expect(snapshot.state == .stopped)
        #expect(snapshot.track == nil)
    }

    @Test func emptyIdentifierMeansNoTrack() {
        let result = list(Self.playing, "", "", "", "", "")

        #expect(AppleScriptPlayerClient.parse(result, player: .spotify, at: .now).track == nil)
    }

    /// AppleScript can't compile a script for an app that isn't on the Mac, such as on CI.
    private func isInstalled(_ player: MusicPlayer) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.bundleIdentifier) != nil
    }

    private func list(_ state: OSType, _ fields: String...) -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.list()
        descriptor.insert(NSAppleEventDescriptor(enumCode: state), at: 1)
        for (offset, field) in fields.enumerated() {
            descriptor.insert(NSAppleEventDescriptor(string: field), at: offset + 2)
        }
        return descriptor
    }
}
