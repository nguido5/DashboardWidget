//
//  DisplayStore.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import AppKit
import Observation

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
}

/// What the menu bar's Display submenu shows.
@MainActor
@Observable
final class DisplayStore {
    static let shared = DisplayStore()

    private(set) var displays: [DisplayInfo] = []
    private(set) var currentID: CGDirectDisplayID = 0

    private init() { refresh(widgetScreen: nil) }

    func refresh(widgetScreen: NSScreen?) {
        let latest = NSScreen.screens.map { DisplayInfo(id: $0.displayID, name: $0.localizedName) }
        if latest != displays { displays = latest }
        if let screen = widgetScreen, screen.displayID != currentID { currentID = screen.displayID }
    }
}
