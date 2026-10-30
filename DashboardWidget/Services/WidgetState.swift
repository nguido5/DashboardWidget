//
//  WidgetState.swift
//  DashboardWidget
//

import Foundation
import Observation

/// Live window state that views and the menu bar react to.
@MainActor
@Observable
final class WidgetState {
    static let shared = WidgetState()

    /// The widget fills its display in its own full-screen space.
    var isFullScreen = false

    /// False when the widget is hidden, fully covered, or the display is asleep/locked.
    /// Modules use this to stop polling and animating when nobody can see them.
    var isOnScreen = true {
        didSet {
            guard isOnScreen != oldValue else { return }
            SpotifyController.shared.visibilityChanged()
        }
    }

    private init() {}
}

/// Actions shared by the menu bar and the widget.
@MainActor
enum AppActions {
    /// Re-fetches every module right away.
    static func refreshAll() {
        EventKitManager.shared.reload()
        Task { await WeatherController.shared.refresh() }
        Task { await SpotifyController.shared.refresh() }
    }
}
