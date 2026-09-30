//
//  DashboardWidgetApp.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

@main
struct DashboardWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Dashboard", systemImage: "square.grid.2x2") {
            Button("Quit DashboardWidget") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
