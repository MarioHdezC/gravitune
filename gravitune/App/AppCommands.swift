//
//  AppCommands.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import SwiftUI
import VisualEngine

struct AppCommands: Commands {
    let nowPlaying: NowPlayingViewModel
    @Bindable var dock: DockViewModel
    @Bindable var settings: VisualSettingsViewModel

    var body: some Commands {
        CommandMenu("Playback") {
            Button("Play or Pause", action: nowPlaying.togglePlayPause)
                .keyboardShortcut(.space, modifiers: [])
            Button("Next", action: nowPlaying.skipToNext)
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous", action: nowPlaying.skipToPrevious)
                .keyboardShortcut(.leftArrow, modifiers: .command)
        }
        CommandMenu("Visual") {
            Toggle("Show Controls", isOn: $dock.isOpen)
                .keyboardShortcut("h", modifiers: [])
            Divider()
            Picker("Style", selection: $settings.settings.style) {
                ForEach(FlowStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
        }
    }
}
