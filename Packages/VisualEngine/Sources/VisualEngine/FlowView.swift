//
//  FlowView.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import MetalKit
import SwiftUI

/// How each frame reaches the screen.
public enum FlowPresentation: Sendable {
    /// Presents directly with Metal: the most efficient option.
    case direct
    /// Delivers it as a regular layer's contents; needed on external AirPlay displays.
    case composited
}

/// Shows a `FlowRenderer`'s fluid background; the renderer must outlive the view.
@MainActor
public struct FlowView {
    private let renderer: FlowRenderer
    private let presentation: FlowPresentation

    public init(renderer: FlowRenderer, presentation: FlowPresentation = .direct) {
        self.renderer = renderer
        self.presentation = presentation
    }

    private func makeMetalView() -> MTKView {
        let view = makeView()
        view.colorPixelFormat = FlowRenderer.outputFormat
        view.preferredFramesPerSecond = 60
        view.delegate = renderer
        return view
    }

    private func makeView() -> MTKView {
        #if os(macOS)
        if presentation == .composited {
            return SurfaceFlowView(frame: .zero, device: renderer.device)
        }
        #endif
        return MTKView(frame: .zero, device: renderer.device)
    }
}

#if os(macOS)
extension FlowView: NSViewRepresentable {
    public func makeNSView(context: Context) -> MTKView { makeMetalView() }
    public func updateNSView(_ view: MTKView, context: Context) {}
}
#else
extension FlowView: UIViewRepresentable {
    public func makeUIView(context: Context) -> MTKView { makeMetalView() }
    public func updateUIView(_ view: MTKView, context: Context) {}
}
#endif
