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
    let eventID: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

struct TimeCalendarView: View {
    private let manager = EventKitManager.shared
    @AppStorage(PrefKey.includeAllDay) private var includeAllDay = false
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
        .task(id: "\(manager.eventsAuthorized)-\(manager.changeToken)-\(includeAllDay)") {
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
                // Re-evaluated every minute so "in 25 min" counts down and "now" appears on time.
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 4) {
                        ForEach(events) { row($0, now: context.date) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ event: UpcomingEvent, now: Date) -> some View {
        let live = !event.isAllDay && event.start <= now && event.end > now
        return Button { open(event) } label: {
            HStack(spacing: 8) {
                Circle().fill(event.color).frame(width: 8, height: 8)
                Text(event.title)
                    .font(.system(size: 13, weight: live ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(timeLabel(event, now: now, live: live))
                    .font(.system(size: 12, weight: live ? .semibold : .regular))
                    .foregroundStyle(live ? Color.primary : Color.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(live ? Color.white.opacity(0.12) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in Calendar")
    }

    private func timeLabel(_ event: UpcomingEvent, now: Date, live: Bool) -> String {
        let cal = Calendar.current

        if event.isAllDay {
            if event.start <= now || cal.isDateInToday(event.start) { return "All day" }
            if cal.isDateInTomorrow(event.start) { return "Tomorrow" }
            return event.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }

        if live { return "until " + event.end.formatted(date: .omitted, time: .shortened) }

        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "in \(max(minutes, 1)) min" }

        let time = event.start.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(event.start) { return time }
        if cal.isDateInTomorrow(event.start) { return "Tomorrow \(time)" }
        return event.start.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }

    private func open(_ event: UpcomingEvent) {
        guard let id = event.eventID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed), !id.isEmpty else {
            AppLinks.openApp(AppLinks.calendarApp)
            return
        }
        AppLinks.open("ical://ekevent/\(id)?method=show&options=more", fallbackApp: AppLinks.calendarApp)
    }

    private func load() {
        guard manager.eventsAuthorized else { events = []; return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now)!
        let predicate = manager.store.predicateForEvents(withStart: now, end: end, calendars: nil)

        events = manager.store.events(matching: predicate)
            .filter { $0.endDate > now && (includeAllDay || !$0.isAllDay) }   // in-progress events stay
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)
            .map {
                UpcomingEvent(
                    // recurring events share an identifier, so add the start time
                    id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                    eventID: $0.eventIdentifier ?? "",
                    title: $0.title ?? "Untitled",
                    start: $0.startDate,
                    end: $0.endDate,
                    isAllDay: $0.isAllDay,
                    color: Color(nsColor: $0.calendar.color ?? .systemBlue)
                )
            }
    }
}
