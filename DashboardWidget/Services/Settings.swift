//
//  Settings.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import Foundation

/// UserDefaults keys shared by the menu bar and the widget.
enum PrefKey {
    static let allDesktops = "showOnAllDesktops"
    static let alwaysOnTop = "alwaysOnTop"
    static let hidden = "widgetHidden"
    static let includeAllDay = "includeAllDayEvents"
    static let liquidGlass = "useLiquidGlass"
}

extension UserDefaults {
    func flag(_ key: String, default fallback: Bool) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }
}
