//
//  FlowBackground.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import SwiftUI
import VisualEngine

struct FlowBackground: View {
    let renderer: FlowRenderer?
    var presentation = FlowPresentation.direct

    var body: some View {
        if let renderer {
            FlowView(renderer: renderer, presentation: presentation)
        } else {
            ContentUnavailableView("Metal is not available", systemImage: "exclamationmark.triangle")
        }
    }
}
