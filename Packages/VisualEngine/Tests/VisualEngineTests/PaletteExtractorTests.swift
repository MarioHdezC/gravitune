//
//  PaletteExtractorTests.swift
//  VisualEngineTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Testing
@testable import VisualEngine

struct PaletteExtractorTests {
    @Test func solidColorKeepsHueAndGainsDepth() throws {
        let palette = PaletteExtractor.extract(from: try image(fills: [(0.85, 0.1, 0.1)]))

        #expect(palette.colors.count == Palette.stopCount)
        #expect(isAscending(palette))
        #expect(palette.colors[4].lightness - palette.colors[0].lightness > 0.3)
        #expect(palette.colors.allSatisfy { $0.a > 0 })
    }

    @Test func grayscaleCoverStaysNeutral() throws {
        let palette = PaletteExtractor.extract(from: try image(fills: [(0.05, 0.05, 0.05), (0.9, 0.9, 0.9)]))

        #expect(isAscending(palette))
        #expect(palette.colors.allSatisfy { $0.chroma < 0.01 })
    }

    @Test func keepsBothColorsOfATwoColorCover() throws {
        let palette = PaletteExtractor.extract(from: try image(fills: [(0.05, 0.15, 0.85), (0.95, 0.5, 0.05)]))

        #expect(palette.colors.contains { $0.b < -0.1 })
        #expect(palette.colors.contains { $0.b > 0.1 })
    }

    @Test func colorsStayInsideSRGB() throws {
        let palette = PaletteExtractor.extract(from: try image(fills: [(0, 1, 0), (1, 0, 1), (0, 0, 1)]))

        #expect(palette.colors.allSatisfy { $0.isInGamut })
    }

    @Test func extractionIsDeterministic() throws {
        let cover = try image(fills: [(0.2, 0.7, 0.4), (0.8, 0.3, 0.6), (0.1, 0.1, 0.3)])

        #expect(PaletteExtractor.extract(from: cover) == PaletteExtractor.extract(from: cover))
    }

    @Test func fullyTransparentImageFallsBack() throws {
        let cover = try image(fills: [])

        #expect(PaletteExtractor.extract(from: cover) == .fallback)
    }

    private func isAscending(_ palette: Palette) -> Bool {
        zip(palette.colors, palette.colors.dropFirst()).allSatisfy { $0.lightness <= $1.lightness }
    }

    /// Creates an image with one vertical stripe per color.
    private func image(fills: [(CGFloat, CGFloat, CGFloat)]) throws -> CGImage {
        let side = 96
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let width = CGFloat(side) / CGFloat(max(fills.count, 1))
        for (index, fill) in fills.enumerated() {
            context.setFillColor(red: fill.0, green: fill.1, blue: fill.2, alpha: 1)
            context.fill(CGRect(x: CGFloat(index) * width, y: 0, width: width, height: CGFloat(side)))
        }
        return try #require(context.makeImage())
    }
}
