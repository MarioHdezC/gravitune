//
//  Cover.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import Foundation
import VisualEngine

nonisolated struct Cover: Identifiable {
    let id = UUID()
    let image: CGImage
    let palette: Palette

    /// Extracts the palette off the main thread, so the animation isn't interrupted.
    @concurrent
    static func extracted(from image: CGImage) async -> Cover {
        Cover(image: image, palette: PaletteExtractor.extract(from: image))
    }
}
