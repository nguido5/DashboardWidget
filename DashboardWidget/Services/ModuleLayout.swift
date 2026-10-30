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

    /// Fixed card height. Full screen uses these to pick a column layout.
    var height: CGFloat {
        switch self {
        case .clock: 116
        case .weather: 148
        case .calendar: 132
        case .reminders: 220
        case .spotify: 120
        }
    }
}

/// Full-screen arrangement: modules flow top-to-bottom, then into the next column, using
/// whichever column count lets the panel scale up the most on this display.
enum FullScreenLayout {
    static let columnWidth: CGFloat = 320
    static let spacing: CGFloat = 16
    static let padding: CGFloat = 16

    struct Result {
        var columns: [[WidgetModule]]
        var scale: CGFloat
    }

    static func best(for modules: [WidgetModule], in area: CGSize) -> Result {
        guard !modules.isEmpty, area.width > 0, area.height > 0 else { return Result(columns: [modules], scale: 1) }
        let usable = CGSize(width: area.width * 0.94, height: area.height * 0.94)   // breathing room
        var best = Result(columns: [modules], scale: 0)
        for count in 1...modules.count {
            let columns = split(modules, into: count)
            let size = panelSize(columns)
            let scale = min(usable.width / size.width, usable.height / size.height, 3)
            if scale > best.scale + 0.01 { best = Result(columns: columns, scale: scale) }
        }
        return best
    }

    private static func height(of column: [WidgetModule]) -> CGFloat {
        column.reduce(0) { $0 + $1.height } + CGFloat(max(column.count - 1, 0)) * spacing
    }

    private static func panelSize(_ columns: [[WidgetModule]]) -> CGSize {
        let n = CGFloat(columns.count)
        return CGSize(
            width: n * columnWidth + (n - 1) * spacing + padding * 2,
            height: (columns.map { height(of: $0) }.max() ?? 0) + padding * 2
        )
    }

    /// Splits the list, in order, into `count` columns with the shortest tallest column.
    private static func split(_ modules: [WidgetModule], into count: Int) -> [[WidgetModule]] {
        if count <= 1 { return [modules] }
        var best: [[WidgetModule]] = [modules]
        var bestHeight = CGFloat.infinity
        for cut in 1...(modules.count - count + 1) {
            let rest = split(Array(modules[cut...]), into: count - 1)
            let candidate = [Array(modules[..<cut])] + rest
            let tallest = candidate.map { height(of: $0) }.max() ?? 0
            if tallest < bestHeight { bestHeight = tallest; best = candidate }
        }
        return best
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
