//
//  FlowRenderer.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import MetalKit
import QuartzCore
import Synchronization

public enum FlowStyle: Int32, CaseIterable, Identifiable, Sendable {
    case liquid
    case ocean
    case aurora

    public var id: Int32 { rawValue }
}

public struct FlowSettings: Equatable, Sendable {
    public var style: FlowStyle = .liquid
    public var speed: Float = 0.18
    public var scale: Float = 1.3
    public var warp: Float = 2.2
    /// Fraction of the screen resolution at which the fluid is computed.
    public var renderScale: Float = 0.35

    public init() {}
}

// Must exactly match `FlowUniforms` in Flow.metal.
struct FlowUniforms {
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var color3: SIMD4<Float>
    var color4: SIMD4<Float>
    var resolution: SIMD2<Float>
    var time: Float
    var style: Int32
    var scale: Float
    var warp: Float
    var padding: SIMD2<Float> = .zero
}

/// Measures GPU time in the background, without touching the main thread.
private final class GPUTimer: Sendable {
    private let average = Mutex<Double>(0)

    var milliseconds: Double { average.withLock { $0 } }

    func record(_ seconds: Double) {
        let milliseconds = seconds * 1000
        average.withLock { $0 += ($0 == 0 ? 1 : 0.05) * (milliseconds - $0) }
    }
}

@MainActor
public final class FlowRenderer: NSObject, MTKViewDelegate {
    static let outputFormat = MTLPixelFormat.bgra8Unorm
    private static let flowFormat = MTLPixelFormat.rgba16Float
    private static let paletteTransition: Double = 2.5
    private static let maxFrameDelta: Double = 0.1

    public let device: MTLDevice
    public var settings = FlowSettings()

    /// Average GPU time per frame.
    public var gpuMilliseconds: Double { timer.milliseconds }

    private let commandQueue: MTLCommandQueue
    private let flowPipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let timer = GPUTimer()

    private var flowTexture: MTLTexture?
    private var sourcePalette = Palette.fallback
    private var targetPalette = Palette.fallback
    private var transition = 1.0
    private var phase = 0.0
    private var lastFrame: CFTimeInterval?

    public init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device,
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .module),
              let flowPipeline = Self.pipeline(device, library, "flowFragment", Self.flowFormat),
              let presentPipeline = Self.pipeline(device, library, "presentFragment", Self.outputFormat)
        else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.flowPipeline = flowPipeline
        self.presentPipeline = presentPipeline
    }

    private static func pipeline(
        _ device: MTLDevice,
        _ library: MTLLibrary,
        _ fragment: String,
        _ format: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "fullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.colorAttachments[0].pixelFormat = format
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// Changes palette smoothly, starting from the color visible at that moment.
    public func setPalette(_ palette: Palette, animated: Bool = true) {
        sourcePalette = animated ? currentPalette : palette
        targetPalette = palette
        transition = animated ? 0 : 1
    }

    private var currentPalette: Palette {
        let eased = Float(transition * transition * (3 - 2 * transition))
        return sourcePalette.mixed(with: targetPalette, by: eased)
    }

    func advance(by delta: Double) {
        phase += delta * Double(settings.speed)
        transition = min(transition + delta / Self.paletteTransition, 1)
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        advance(by: min(now - (lastFrame ?? now), Self.maxFrameDelta))
        lastFrame = now

        #if os(macOS)
        if let surfaceView = view as? SurfaceFlowView {
            drawToSurface(of: surfaceView)
            return
        }
        #endif

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        encode(into: commandBuffer, target: drawable.texture)
        commandBuffer.present(drawable)
        let timer = self.timer
        commandBuffer.addCompletedHandler { buffer in
            timer.record(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        commandBuffer.commit()
    }

    #if os(macOS)
    /// If no surface is free, the frame is skipped instead of waiting for the GPU.
    private func drawToSurface(of view: SurfaceFlowView) {
        guard let (surface, pool) = view.acquireSurface() else { return }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            pool.release(surface)
            return
        }

        encode(into: commandBuffer, target: surface.texture)
        let timer = self.timer
        commandBuffer.addCompletedHandler { buffer in
            timer.record(buffer.gpuEndTime - buffer.gpuStartTime)
            Task { @MainActor in
                view.show(surface, from: pool)
            }
        }
        commandBuffer.commit()
    }
    #endif

    // MARK: - Drawing

    func encode(into commandBuffer: MTLCommandBuffer, target: MTLTexture) {
        guard let flowTexture = flowTexture(matching: target) else { return }

        let flowPass = MTLRenderPassDescriptor()
        flowPass.colorAttachments[0].texture = flowTexture
        flowPass.colorAttachments[0].loadAction = .dontCare
        flowPass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: flowPass) {
            var uniforms = makeUniforms(for: flowTexture)
            encoder.setRenderPipelineState(flowPipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlowUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        let presentPass = MTLRenderPassDescriptor()
        presentPass.colorAttachments[0].texture = target
        presentPass.colorAttachments[0].loadAction = .dontCare
        presentPass.colorAttachments[0].storeAction = .store
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: presentPass) {
            encoder.setRenderPipelineState(presentPipeline)
            encoder.setFragmentTexture(flowTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }

    private func flowTexture(matching target: MTLTexture) -> MTLTexture? {
        let scale = Double(settings.renderScale)
        let width = max(Int(Double(target.width) * scale), 2)
        let height = max(Int(Double(target.height) * scale), 2)
        if let flowTexture, flowTexture.width == width, flowTexture.height == height {
            return flowTexture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.flowFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        flowTexture = device.makeTexture(descriptor: descriptor)
        return flowTexture
    }

    private func makeUniforms(for texture: MTLTexture) -> FlowUniforms {
        let colors = currentPalette.colors.map { SIMD4($0.vector, 0) }
        return FlowUniforms(
            color0: colors[0],
            color1: colors[1],
            color2: colors[2],
            color3: colors[3],
            color4: colors[4],
            resolution: SIMD2(Float(texture.width), Float(texture.height)),
            time: Float(phase),
            style: settings.style.rawValue,
            scale: settings.scale,
            warp: settings.warp
        )
    }
}
