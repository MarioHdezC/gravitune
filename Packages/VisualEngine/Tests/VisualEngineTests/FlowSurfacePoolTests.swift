//
//  FlowSurfacePoolTests.swift
//  VisualEngineTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Metal
import Testing
@testable import VisualEngine

@MainActor
struct FlowSurfacePoolTests {
    private func makePool(width: Int, height: Int) throws -> FlowSurfacePool {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try #require(FlowSurfacePool(device: device, pixelFormat: .bgra8Unorm, width: width, height: height))
    }

    // Real sizes, including the 1366-wide TV, whose rows aren't naturally aligned.
    @Test(arguments: [(1366, 768), (1, 1), (1921, 1081), (3840, 2160)])
    func createsSurfacesForAnyScreenSize(width: Int, height: Int) throws {
        let surface = try #require(try makePool(width: width, height: height).acquire())

        #expect(surface.texture.width == width)
        #expect(surface.surface.height == height)
    }

    @Test func rejectsEmptySizes() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())

        #expect(FlowSurfacePool(device: device, pixelFormat: .bgra8Unorm, width: 0, height: 768) == nil)
    }

    @Test func runsOutOfSurfacesAndRecoversWhenReleased() throws {
        let pool = try makePool(width: 64, height: 64)
        let surfaces = (0..<3).compactMap { _ in pool.acquire() }

        #expect(surfaces.count == 3)
        #expect(pool.acquire() == nil)

        pool.release(surfaces[0])

        #expect(pool.acquire() != nil)
    }

    @Test func rendererDrawsColorIntoASurface() throws {
        let renderer = try #require(FlowRenderer())
        let surface = try #require(try makePool(width: 1366, height: 768).acquire())
        let commandBuffer = try #require(renderer.device.makeCommandQueue()?.makeCommandBuffer())

        renderer.encode(into: commandBuffer, target: surface.texture)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        var pixels = [UInt32](repeating: 0, count: 1366 * 768)
        pixels.withUnsafeMutableBytes { buffer in
            surface.texture.getBytes(
                buffer.baseAddress!,
                bytesPerRow: 1366 * 4,
                from: MTLRegionMake2D(0, 0, 1366, 768),
                mipmapLevel: 0
            )
        }

        #expect(commandBuffer.status == .completed)
        #expect(Set(pixels).count > 50)
    }
}
