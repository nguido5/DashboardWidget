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
    @ObservationIgnored private var pendingChange: Task<Void, Never>?

    var eventsAuthorized = false
    var remindersAuthorized = false
    /// Bumps whenever anything in Calendar/Reminders changes, so views can refresh.
    var changeToken = 0

    private init() {
        let center = NotificationCenter.default
        observer = center.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            guard let manager = self else { return }
            Task { @MainActor in manager.scheduleChange() }
        }
        // Midnight rollover and clock/time-zone changes: "today" means something new.
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            dayObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let manager = self else { return }
                Task { @MainActor in manager.scheduleChange() }
            })
        }
    }

    @ObservationIgnored private var dayObservers: [NSObjectProtocol] = []

    func requestAccess() async {
        eventsAuthorized = (try? await store.requestFullAccessToEvents()) ?? false
        remindersAuthorized = (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Forces both modules to re-fetch now.
    func reload() {
        pendingChange?.cancel()
        changeToken += 1
    }

    /// iCloud syncs often post several change notifications in a burst; reload once per burst.
    private func scheduleChange() {
        pendingChange?.cancel()
        pendingChange = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            changeToken += 1
        }
    }
}
