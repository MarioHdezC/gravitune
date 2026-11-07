//
//  ArtworkLoaderTests.swift
//  NowPlayingTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Foundation
import Testing
@testable import NowPlaying

struct ArtworkLoaderTests {
    private func track(artist: String = "Artist", album: String = "Album & Co") -> NowPlayingTrack {
        NowPlayingTrack(player: .spotify, id: "1", title: "Song", artist: artist, album: album, artworkURL: nil)
    }

    @Test func buildsAnEscapedCatalogSearch() throws {
        let url = try #require(ArtworkLoader.catalogSearchURL(for: track(), region: "ES"))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        #expect(url.host() == "itunes.apple.com")
        #expect(items.contains(URLQueryItem(name: "term", value: "Artist Album & Co")))
        #expect(items.contains(URLQueryItem(name: "country", value: "ES")))
    }

    @Test func doesNotSearchWithoutArtistOrAlbum() {
        #expect(ArtworkLoader.catalogSearchURL(for: track(artist: "")) == nil)
        #expect(ArtworkLoader.catalogSearchURL(for: track(album: "")) == nil)
    }

    @Test func requestsTheLargeCatalogImage() {
        let response = Data(#"{"results":[{"artworkUrl100":"https://is1.mzstatic.com/a/100x100bb.jpg"}]}"#.utf8)

        let url = ArtworkLoader.artworkURL(fromCatalogResponse: response)

        #expect(url?.absoluteString == "https://is1.mzstatic.com/a/1200x1200bb.jpg")
    }

    @Test func emptyCatalogResponseHasNoArtwork() {
        #expect(ArtworkLoader.artworkURL(fromCatalogResponse: Data(#"{"results":[]}"#.utf8)) == nil)
    }

    @Test func invalidImageDataIsRejected() {
        #expect(ArtworkLoader.decode(Data("not an image".utf8)) == nil)
    }
}
