//
//  Palette.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import SwiftUI
import simd

/// Color in OKLab, a perceptual space: mixing here doesn't produce muddy tones.
public struct OKLabColor: Equatable, Sendable {
    public var lightness: Float
    public var a: Float
    public var b: Float

    public init(lightness: Float, a: Float, b: Float) {
        self.lightness = lightness
        self.a = a
        self.b = b
    }

    /// Creates a color from sRGB components between 0 and 1.
    public init(red: Float, green: Float, blue: Float) {
        let r = Self.toLinear(red)
        let g = Self.toLinear(green)
        let b = Self.toLinear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        self.lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        self.a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        self.b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    public var chroma: Float { (a * a + b * b).squareRoot() }

    /// sRGB components between 0 and 1, clipped to the visible gamut.
    public var sRGB: SIMD3<Float> {
        let linear = linearSRGB
        return SIMD3(Self.toGamma(linear.x), Self.toGamma(linear.y), Self.toGamma(linear.z))
    }

    public var color: Color {
        let components = sRGB
        return Color(.sRGB, red: Double(components.x), green: Double(components.y), blue: Double(components.z))
    }

    var vector: SIMD3<Float> { SIMD3(lightness, a, b) }

    var isInGamut: Bool {
        let linear = linearSRGB
        return linear.min() >= -0.001 && linear.max() <= 1.001
    }

    func mixed(with other: OKLabColor, by amount: Float) -> OKLabColor {
        let mixed = simd_mix(vector, other.vector, SIMD3(repeating: amount))
        return OKLabColor(lightness: mixed.x, a: mixed.y, b: mixed.z)
    }

    /// Reduces chroma until the color fits in sRGB, preserving hue and lightness.
    func fittedToGamut() -> OKLabColor {
        guard !isInGamut else { return self }
        var low: Float = 0
        var high: Float = 1
        for _ in 0..<12 {
            let middle = (low + high) / 2
            let candidate = OKLabColor(lightness: lightness, a: a * middle, b: b * middle)
            if candidate.isInGamut { low = middle } else { high = middle }
        }
        return OKLabColor(lightness: lightness, a: a * low, b: b * low)
    }

    private var linearSRGB: SIMD3<Float> {
        let l = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = lightness - 0.0894841775 * a - 1.2914855480 * b
        let (l3, m3, s3) = (l * l * l, m * m * m, s * s * s)
        return SIMD3(
            4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
            -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
            -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
        )
    }

    private static func toLinear(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ value: Float) -> Float {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}

/// Five-color ramp, ordered from dark to light.
public struct Palette: Equatable, Sendable {
    public static let stopCount = 5
    private static let accentLightness: Float = 0.82
    private static let neutralAccentLightness: Float = 0.96
    private static let minimumAccentChroma: Float = 0.03

    public static let fallback = Palette(colors: [
        OKLabColor(lightness: 0.16, a: 0.01, b: -0.05),
        OKLabColor(lightness: 0.32, a: 0.02, b: -0.09),
        OKLabColor(lightness: 0.48, a: 0.03, b: -0.12),
        OKLabColor(lightness: 0.64, a: 0.02, b: -0.10),
        OKLabColor(lightness: 0.80, a: 0.01, b: -0.06)
    ])

    public let colors: [OKLabColor]

    /// Controls color: the most vivid hue, lightened to read over a dark panel.
    /// Nearly neutral palettes give white.
    public var accent: OKLabColor {
        guard let vivid = colors.max(by: { $0.chroma < $1.chroma }),
              vivid.chroma >= Self.minimumAccentChroma else {
            return OKLabColor(lightness: Self.neutralAccentLightness, a: 0, b: 0)
        }
        return OKLabColor(lightness: Self.accentLightness, a: vivid.a, b: vivid.b).fittedToGamut()
    }

    public init(colors: [OKLabColor]) {
        precondition(colors.count == Self.stopCount)
        self.colors = colors
    }

    func mixed(with other: Palette, by amount: Float) -> Palette {
        Palette(colors: zip(colors, other.colors).map { $0.mixed(with: $1, by: amount) })
    }
}
