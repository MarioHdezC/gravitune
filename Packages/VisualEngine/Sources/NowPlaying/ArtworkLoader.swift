//
//  ArtworkLoader.swift
//  NowPlaying
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Foundation
import ImageIO

protocol ArtworkLoading: Sendable {
    func artwork(for track: NowPlayingTrack, embedded: Data?) async -> CGImage?
}

/// Tries, in order, the player's image, its link and, finally, the iTunes catalog.
struct ArtworkLoader: ArtworkLoading {
    private static let maxSide = 1600

    private struct SearchResponse: Decodable {
        struct Album: Decodable {
            let artworkUrl100: URL?
        }
        let results: [Album]
    }

    func artwork(for track: NowPlayingTrack, embedded: Data?) async -> CGImage? {
        if let embedded, let image = Self.decode(embedded) { return image }
        if let url = track.artworkURL, let image = await image(at: url) { return image }
        guard let url = await catalogArtworkURL(for: track) else { return nil }
        return await image(at: url)
    }

    private func image(at url: URL) async -> CGImage? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return Self.decode(data)
    }

    private func catalogArtworkURL(for track: NowPlayingTrack) async -> URL? {
        guard let url = Self.catalogSearchURL(for: track),
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return Self.artworkURL(fromCatalogResponse: data)
    }

    static func catalogSearchURL(for track: NowPlayingTrack, region: String? = Locale.current.region?.identifier) -> URL? {
        guard !track.artist.isEmpty, !track.album.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: "\(track.artist) \(track.album)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "album"),
            URLQueryItem(name: "limit", value: "1")
        ]
        if let region {
            components?.queryItems?.append(URLQueryItem(name: "country", value: region))
        }
        return components?.url
    }

    static func artworkURL(fromCatalogResponse data: Data) -> URL? {
        guard let response = try? JSONDecoder().decode(SearchResponse.self, from: data),
              let thumbnail = response.results.first?.artworkUrl100 else { return nil }
        return URL(string: thumbnail.absoluteString.replacingOccurrences(of: "100x100", with: "1200x1200"))
    }

    static func decode(_ data: Data) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
