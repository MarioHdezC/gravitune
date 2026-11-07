//
//  FlowStyle+Title.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import SwiftUI
import VisualEngine

extension FlowStyle {
    var title: LocalizedStringKey {
        switch self {
        case .liquid: "Liquid"
        case .ocean: "Ocean"
        case .aurora: "Aurora"
        }
    }
}
