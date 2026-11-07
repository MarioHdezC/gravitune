//
//  PaletteExtractor.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import CoreGraphics
import simd

/// Gets a palette suited to the background from an artwork.
public enum PaletteExtractor {
    private static let sampleSide = 48
    private static let clusterCount = 8
    private static let iterations = 12

    /// It's deterministic: the same image always produces the same palette.
    public static func extract(from image: CGImage) -> Palette {
        let samples = samples(from: image)
        guard !samples.isEmpty else { return .fallback }
        let clusters = cluster(samples)
        return shaped(pickStops(from: clusters, sampleCount: samples.count))
    }

    // MARK: - Sampling

    private static func samples(from image: CGImage) -> [SIMD3<Float>] {
        var pixels = [UInt8](repeating: 0, count: sampleSide * sampleSide * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: sampleSide,
                    height: sampleSide,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleSide * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))
            return true
        }
        guard drawn else { return [] }

        var result: [SIMD3<Float>] = []
        result.reserveCapacity(sampleSide * sampleSide)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Float(pixels[offset + 3])
            guard alpha >= 128 else { continue }
            let color = OKLabColor(
                red: Float(pixels[offset]) / alpha,
                green: Float(pixels[offset + 1]) / alpha,
                blue: Float(pixels[offset + 2]) / alpha
            )
            result.append(color.vector)
        }
        return result
    }

    // MARK: - K-means

    private struct Cluster {
        var center: SIMD3<Float>
        var count: Int
    }

    private static func cluster(_ samples: [SIMD3<Float>]) -> [Cluster] {
        var centers = seededCenters(from: samples)
        var assignments = [Int](repeating: 0, count: samples.count)

        for _ in 0..<iterations {
            for (index, sample) in samples.enumerated() {
                assignments[index] = centers.indices.min {
                    distance_squared(sample, centers[$0]) < distance_squared(sample, centers[$1])
                } ?? 0
            }
            var sums = [SIMD3<Float>](repeating: .zero, count: centers.count)
            var counts = [Int](repeating: 0, count: centers.count)
            for (index, sample) in samples.enumerated() {
                sums[assignments[index]] += sample
                counts[assignments[index]] += 1
            }
            for index in centers.indices where counts[index] > 0 {
                centers[index] = sums[index] / Float(counts[index])
            }
        }

        var counts = [Int](repeating: 0, count: centers.count)
        for assignment in assignments { counts[assignment] += 1 }
        return zip(centers, counts).filter { $0.1 > 0 }.map { Cluster(center: $0, count: $1) }
    }

    /// Seeds by maximum distance, without randomness, so the result is reproducible.
    private static func seededCenters(from samples: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var centers = [samples.reduce(.zero, +) / Float(samples.count)]
        while centers.count < clusterCount {
            var farthest = samples[0]
            var largestDistance: Float = 0
            for sample in samples {
                let nearest = centers.map { distance_squared(sample, $0) }.min() ?? 0
                if nearest > largestDistance {
                    largestDistance = nearest
                    farthest = sample
                }
            }
            guard largestDistance > 1e-5 else { break }
            centers.append(farthest)
        }
        return centers
    }

    // MARK: - Color Selection

    /// Favors vivid, abundant colors and penalizes those similar to the ones already chosen.
    private static func pickStops(from clusters: [Cluster], sampleCount: Int) -> [SIMD3<Float>] {
        func score(_ cluster: Cluster) -> Float {
            let share = Float(cluster.count) / Float(sampleCount)
            let chroma = simd_length(SIMD2(cluster.center.y, cluster.center.z))
            return share.squareRoot() * (1 + 6 * chroma)
        }

        var remaining = clusters
        var picked: [SIMD3<Float>] = []
        while picked.count < Palette.stopCount, !remaining.isEmpty {
            let best = remaining.indices.max { first, second in
                diversified(score(remaining[first]), remaining[first].center, picked)
                    < diversified(score(remaining[second]), remaining[second].center, picked)
            }
            guard let best else { break }
            picked.append(remaining.remove(at: best).center)
        }

        // With few colors they repeat; `shaped` later gives them different lightness values.
        let base = picked
        var index = 0
        while picked.count < Palette.stopCount {
            picked.append(base[index % base.count])
            index += 1
        }
        return picked
    }

    private static func diversified(_ score: Float, _ center: SIMD3<Float>, _ picked: [SIMD3<Float>]) -> Float {
        guard let nearest = picked.map({ simd_distance(center, $0) }).min() else { return score }
        return score * min(nearest / 0.18, 1)
    }

    // MARK: - Background Adjustment

    /// Guarantees tonal depth without fully losing the artwork's light or dark character.
    private static func shaped(_ stops: [SIMD3<Float>]) -> Palette {
        let sorted = stops.sorted { $0.x < $1.x }
        let dominant = stops.max { chroma(of: $0) < chroma(of: $1) } ?? stops[0]
        let isColorful = chroma(of: dominant) > 0.06

        let colors = sorted.enumerated().map { index, stop -> OKLabColor in
            let rank = Float(index) / Float(Palette.stopCount - 1)
            let lightness = simd_mix(stop.x, 0.15 + 0.68 * rank, 0.55)
            var a = stop.y * 1.12
            var b = stop.z * 1.12

            // A white or black inside a colorful artwork would muddy the gradient.
            if isColorful, chroma(of: stop) < 0.03 {
                a = simd_mix(a, dominant.y, 0.35)
                b = simd_mix(b, dominant.z, 0.35)
            }
            return OKLabColor(lightness: min(max(lightness, 0.08), 0.9), a: a, b: b).fittedToGamut()
        }
        return Palette(colors: colors)
    }

    private static func chroma(of color: SIMD3<Float>) -> Float {
        simd_length(SIMD2(color.y, color.z))
    }
}
