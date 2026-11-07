//
//  SurfaceFlowView.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

#if os(macOS)
import MetalKit
import QuartzCore

/// Shows the fluid as a regular layer's contents, instead of presenting with Metal.
///
/// On AirPlay as an extended display, whatever is presented directly with Metal arrives black.
/// `MTKView` is kept only as a clock: it paces the frames.
final class SurfaceFlowView: MTKView {
    private let surfaceLayer = CALayer()
    private var pool: FlowSurfacePool?
    private var displayed: (surface: FlowSurface, pool: FlowSurfacePool)?

    func acquireSurface() -> (surface: FlowSurface, pool: FlowSurfacePool)? {
        guard let device else { return nil }
        let width = Int(drawableSize.width)
        let height = Int(drawableSize.height)
        if pool?.width != width || pool?.height != height {
            pool = FlowSurfacePool(device: device, pixelFormat: colorPixelFormat, width: width, height: height)
        }
        guard let pool, let surface = pool.acquire() else { return nil }
        return (surface, pool)
    }

    func show(_ surface: FlowSurface, from pool: FlowSurfacePool) {
        guard let hostLayer = layer else {
            pool.release(surface)
            return
        }
        if surfaceLayer.superlayer == nil { hostLayer.addSublayer(surfaceLayer) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceLayer.frame = hostLayer.bounds
        surfaceLayer.contents = surface.surface
        CATransaction.commit()

        if let previous = displayed { previous.pool.release(previous.surface) }
        displayed = (surface, pool)
    }
}
#endif
