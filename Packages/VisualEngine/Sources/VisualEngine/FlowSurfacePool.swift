//
//  FlowSurfacePool.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import CoreVideo
import IOSurface
import Metal

/// Image that Metal can draw and Core Animation can show as a layer's contents.
struct FlowSurface: @unchecked Sendable {
    let surface: IOSurface
    let texture: MTLTexture
}

/// Pool of reusable surfaces: one on screen and the rest available for drawing.
@MainActor
final class FlowSurfacePool {
    private static let surfaceCount = 3
    private static let bytesPerPixel = 4

    let width: Int
    let height: Int
    private var available: [FlowSurface]

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        self.width = width
        self.height = height
        let surfaces = (0..<Self.surfaceCount).compactMap { _ in
            Self.makeSurface(device: device, pixelFormat: pixelFormat, width: width, height: height)
        }
        guard surfaces.count == Self.surfaceCount else { return nil }
        available = surfaces
    }

    func acquire() -> FlowSurface? {
        available.popLast()
    }

    func release(_ surface: FlowSurface) {
        available.append(surface)
    }

    private static func makeSurface(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int
    ) -> FlowSurface? {
        // Metal rejects surfaces whose rows don't meet its minimum alignment.
        let alignment = device.minimumLinearTextureAlignment(for: pixelFormat)
        let rowLength = width * bytesPerPixel
        let bytesPerRow = (rowLength + alignment - 1) / alignment * alignment

        guard let surface = IOSurface(properties: [
            .width: width,
            .height: height,
            .bytesPerElement: bytesPerPixel,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: kCVPixelFormatType_32BGRA
        ]) else { return nil }

        let surfaceRef = unsafeBitCast(surface, to: IOSurfaceRef.self)
        // The shader writes sRGB; without this tag, each display would interpret it its own way.
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)?.copyPropertyList() {
            IOSurfaceSetValue(surfaceRef, kIOSurfaceColorSpace, colorSpace)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor, iosurface: surfaceRef, plane: 0) else {
            return nil
        }
        return FlowSurface(surface: surface, texture: texture)
    }
}
