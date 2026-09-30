//
//  EventManagerKit.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import EventKit
import Observation

/// One shared EKEventStore for both calendar and reminders.
@MainActor
@Observable
final class EventKitManager {
    static let shared = EventKitManager()

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?

    var eventsAuthorized = false
    var remindersAuthorized = false
    /// Bumps whenever anything in Calendar/Reminders changes, so views can refresh.
    var changeToken = 0

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            guard let manager = self else { return }
            Task { @MainActor in manager.changeToken += 1 }
        }
    }

    func requestAccess() async {
        eventsAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
        remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
    }
}
