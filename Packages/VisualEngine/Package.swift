// swift-tools-version: 6.2

//
//  Package.swift
//  VisualEngine
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import PackageDescription

let package = Package(
    name: "VisualEngine",
    platforms: [.macOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "VisualEngine", targets: ["VisualEngine"]),
        .library(name: "NowPlaying", targets: ["NowPlaying"])
    ],
    targets: [
        .target(name: "VisualEngine", resources: [.process("Shaders")]),
        .target(name: "NowPlaying"),
        .testTarget(name: "VisualEngineTests", dependencies: ["VisualEngine"]),
        .testTarget(name: "NowPlayingTests", dependencies: ["NowPlaying"])
    ]
)
