//
//  GravituneApp.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import SwiftUI

struct GravituneApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        // A single window: the renderer can only draw into one view.
        Window("Gravitune", id: "main") {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 720)
        .commands {
            AppCommands(nowPlaying: viewModel.nowPlaying, dock: viewModel.dock, settings: viewModel.settings)
        }
    }
}
