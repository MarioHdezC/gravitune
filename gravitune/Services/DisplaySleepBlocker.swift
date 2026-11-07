//
//  DisplaySleepBlocker.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 06/11/2026.
//

import Foundation

/// Keeps the display from sleeping due to inactivity while music is playing.
final class DisplaySleepBlocker {
    private var activity: NSObjectProtocol?

    func setActive(_ isActive: Bool) {
        if isActive, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .idleDisplaySleepDisabled,
                reason: "Showing the music visual"
            )
        } else if !isActive, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }
}
