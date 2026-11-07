//
//  PaletteTests.swift
//  VisualEngineTests
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Testing
@testable import VisualEngine

struct PaletteTests {
    private func palette(a: Float, b: Float) -> Palette {
        Palette(colors: [0.2, 0.35, 0.5, 0.65, 0.8].map { OKLabColor(lightness: $0, a: a, b: b) })
    }

    @Test func accentKeepsTheHueOfTheMostVividColor() {
        let colors = [
            OKLabColor(lightness: 0.2, a: 0.01, b: 0.01),
            OKLabColor(lightness: 0.35, a: 0.02, b: 0.01),
            OKLabColor(lightness: 0.5, a: 0.16, b: 0.08),
            OKLabColor(lightness: 0.65, a: 0.03, b: 0.02),
            OKLabColor(lightness: 0.8, a: 0.01, b: 0.01)
        ]

        let accent = Palette(colors: colors).accent

        #expect(accent.a > 0.05)
        #expect(accent.a / accent.b > 1.9 && accent.a / accent.b < 2.1)
    }

    @Test func accentIsLightEnoughForADarkPanel() {
        #expect(palette(a: -0.1, b: -0.15).accent.lightness >= 0.8)
    }

    @Test func neutralPaletteGivesWhite() {
        let accent = palette(a: 0.005, b: 0).accent

        #expect(accent.chroma == 0)
        #expect(accent.lightness > 0.95)
    }

    @Test(arguments: [(Float(0.3), Float(0.2)), (-0.3, 0.2), (0.1, -0.3), (-0.2, -0.2)])
    func accentStaysInsideSRGB(a: Float, b: Float) {
        #expect(palette(a: a, b: b).accent.isInGamut)
    }
}
