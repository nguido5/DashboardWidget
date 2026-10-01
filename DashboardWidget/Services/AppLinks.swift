//
//  AppLinks.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import AppKit

/// Opens a deep link, falling back to just launching the app if the link doesn't work.
@MainActor
enum AppLinks {
    static let calendarApp = "/System/Applications/Calendar.app"
    static let remindersApp = "/System/Applications/Reminders.app"

    static func open(_ urlString: String, fallbackApp: String) {
        guard let url = URL(string: urlString) else { openApp(fallbackApp); return }
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil {
                Task { @MainActor in AppLinks.openApp(fallbackApp) }
            }
        }
    }

    static func openApp(_ path: String) {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
