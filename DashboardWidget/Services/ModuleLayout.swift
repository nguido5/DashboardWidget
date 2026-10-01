//
//  ModuleLayout.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import Foundation

extension PrefKey {
    static let moduleOrder = "moduleOrder"
    static let hiddenModules = "hiddenModules"
    static let weatherName = "weatherName"
    static let weatherLat = "weatherLatitude"
    static let weatherLon = "weatherLongitude"
    static let weatherCelsius = "weatherCelsius"
}

enum WeatherDefaults {
    static let name = "Atlanta"
    static let latitude = 33.749
    static let longitude = -84.388
}

/// The default order is the declaration order below.
enum WidgetModule: String, CaseIterable, Identifiable {
    case clock, weather, calendar, reminders, spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Time & Date"
        case .weather: "Weather"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .spotify: "Spotify"
        }
    }
}

/// Reads and writes the saved order / hidden list (stored as comma-separated strings).
enum ModuleLayout {
    /// Saved order, ignoring junk; any module missing from it is appended at the end.
    static func order(from raw: String) -> [WidgetModule] {
        var result: [WidgetModule] = []
        for part in raw.split(separator: ",") {
            if let module = WidgetModule(rawValue: String(part)), !result.contains(module) {
                result.append(module)
            }
        }
        for module in WidgetModule.allCases where !result.contains(module) {
            result.append(module)
        }
        return result
    }

    static func hidden(from raw: String) -> Set<WidgetModule> {
        Set(raw.split(separator: ",").compactMap { WidgetModule(rawValue: String($0)) })
    }

    static func serialize(_ modules: some Sequence<WidgetModule>) -> String {
        modules.map(\.rawValue).joined(separator: ",")
    }

    static func visible(orderRaw: String, hiddenRaw: String) -> [WidgetModule] {
        let hidden = hidden(from: hiddenRaw)
        return order(from: orderRaw).filter { !hidden.contains($0) }
    }
}
