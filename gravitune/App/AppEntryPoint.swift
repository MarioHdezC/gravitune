//
//  AppEntryPoint.swift
//  gravitune
//
//  Created by Mario Hernández Corral on 07/11/2026.
//

import Foundation
import SwiftUI

/// Starts an empty app under test, so tests don't launch the visual or contact the players.
@main
enum AppEntryPoint {
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func main() {
        if isRunningTests {
            TestHostApp.main()
        } else {
            GravituneApp.main()
        }
    }
}

private struct TestHostApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
