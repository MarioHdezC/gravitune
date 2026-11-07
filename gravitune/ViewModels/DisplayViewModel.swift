//
//  DisplayViewModel.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import AppKit
import Observation

enum DisplayAvailability: Equatable {
    /// macOS is mirroring the displays, so the visual can't be sent to just one of them.
    case mirroring
    case noExternalDisplays
    case available([ExternalDisplay])
}

/// Choice of the display that shows the visual.
@Observable
final class DisplayViewModel {
    private let router: any DisplayRouting

    init(router: any DisplayRouting = DisplayRouter()) {
        self.router = router
    }

    var availability: DisplayAvailability {
        if router.isMirroring { return .mirroring }
        return router.availableDisplays.isEmpty ? .noExternalDisplays : .available(router.availableDisplays)
    }

    /// Selected external display; `nil` shows the visual in the main window.
    var selectedDisplayID: CGDirectDisplayID? {
        get { router.selectedDisplayID }
        set { router.selectedDisplayID = newValue }
    }

    var selectedDisplay: ExternalDisplay? {
        router.availableDisplays.first { $0.id == selectedDisplayID }
    }

    func run(makeStageView: @escaping @MainActor () -> NSView) async {
        await router.run(makeStageView: makeStageView)
    }

    func returnToThisDisplay() {
        selectedDisplayID = nil
    }
}
