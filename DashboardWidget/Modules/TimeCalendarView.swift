//
//  TimeCalendarView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI
import EventKit

struct UpcomingEvent: Identifiable {
    let id: String
    let title: String
    let start: Date
    let color: Color
}

struct TimeCalendarView: View {
    private let manager = EventKitManager.shared
    @State private var events: [UpcomingEvent] = []

    var body: some View {
        VStack(spacing: 10) {
            clock
            Divider().overlay(.white.opacity(0.15))
            eventsList
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 210)                 // fixed module height
        .moduleCard()
        .task(id: "\(manager.eventsAuthorized)-\(manager.changeToken)") {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(for: .seconds(60))   // also drops events once they end
            }
        }
    }

    // MARK: Clock

    private var clock: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 54, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Events

    @ViewBuilder
    private var eventsList: some View {
        Group {
            if !manager.eventsAuthorized {
                VStack(spacing: 6) {
                    Text("Calendar access needed")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link).font(.caption)
                }
            } else if events.isEmpty {
                Text("No upcoming events")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(events) { row($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ event: UpcomingEvent) -> some View {
        HStack(spacing: 8) {
            Circle().fill(event.color).frame(width: 8, height: 8)
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(timeLabel(event.start))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func timeLabel(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return time }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    private func load() {
        guard manager.eventsAuthorized else { events = []; return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        let predicate = manager.store.predicateForEvents(withStart: now, end: end, calendars: nil)

        events = manager.store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }     // skips all-day; in-progress events stay
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map {
                UpcomingEvent(
                    // recurring events share an identifier, so add the start time
                    id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                    title: $0.title ?? "Untitled",
                    start: $0.startDate,
                    color: Color(nsColor: $0.calendar.color ?? .systemBlue)
                )
            }
    }
}
