//
//  FlowRendererTests.swift
//  VisualEngineTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import VisualEngine

@MainActor
struct FlowRendererTests {
    private static let width = 1280
    private static let height = 720
    private static let palettes: [(String, Palette)] = [
        ("blue", .fallback),
        ("sunset", palette(lightness: [0.2, 0.42, 0.6, 0.75, 0.88], a: [0.08, 0.2, 0.2, 0.12, 0.02], b: [-0.13, -0.05, 0.05, 0.14, 0.16])),
        ("gray", palette(lightness: [0.16, 0.32, 0.5, 0.67, 0.83], a: [0, 0, 0, 0, 0], b: [0, 0, 0, 0, 0]))
    ]

    private static func palette(lightness: [Float], a: [Float], b: [Float]) -> Palette {
        Palette(colors: lightness.indices.map { OKLabColor(lightness: lightness[$0], a: a[$0], b: b[$0]) })
    }

    @Test func uniformsMatchTheShaderLayout() {
        #expect(MemoryLayout<FlowUniforms>.stride == 112)
    }

    @Test(arguments: FlowStyle.allCases)
    func everyStyleRendersVaryingColors(style: FlowStyle) throws {
        let renderer = try #require(FlowRenderer())
        renderer.settings.style = style
        renderer.advance(by: 200)

        for (name, palette) in Self.palettes {
            renderer.setPalette(palette, animated: false)
            let pixels = try render(renderer)

            #expect(Set(pixels).count > 50)
            try exportIfRequested(pixels, name: "\(style)-\(name)")
        }
    }

    @Test func paletteTransitionsGradually() throws {
        let renderer = try #require(FlowRenderer())
        let target = Palette(colors: Palette.fallback.colors.map {
            OKLabColor(lightness: $0.lightness, a: 0.15, b: 0.1)
        })
        renderer.setPalette(.fallback, animated: false)
        let before = try render(renderer)

        renderer.setPalette(target)
        let start = try render(renderer)
        renderer.advance(by: 100)
        let end = try render(renderer)

        #expect(start == before)
        #expect(end != before)
    }

    private func render(_ renderer: FlowRenderer) throws -> [UInt32] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FlowRenderer.outputFormat,
            width: Self.width,
            height: Self.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try #require(renderer.device.makeTexture(descriptor: descriptor))
        let commandBuffer = try #require(renderer.device.makeCommandQueue()?.makeCommandBuffer())

        renderer.encode(into: commandBuffer, target: target)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        #expect(commandBuffer.status == .completed)

        var pixels = [UInt32](repeating: 0, count: Self.width * Self.height)
        pixels.withUnsafeMutableBytes { buffer in
            target.getBytes(
                buffer.baseAddress!,
                bytesPerRow: Self.width * 4,
                from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// With `SNAPSHOT_DIR`, saves the frame as a PNG for visual review.
    private func exportIfRequested(_ pixels: [UInt32], name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixels = pixels
        let image = try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress,
                width: Self.width,
                height: Self.height,
                bitsPerComponent: 8,
                bytesPerRow: Self.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ))
            return try #require(context.makeImage())
        }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}
