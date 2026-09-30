//
//  RemindersView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI
import EventKit

/// Plain, thread-safe snapshot of a reminder (EKReminder itself can't cross threads safely).
nonisolated struct ReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let hasTime: Bool
    let isOverdue: Bool
    let color: Color
    var isCompleted: Bool

    init(reminder: EKReminder) {
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? "Untitled"
        color = Color(nsColor: reminder.calendar?.color ?? .systemBlue)   // the list's color
        isCompleted = reminder.isCompleted

        let cal = Calendar.current
        if let comps = reminder.dueDateComponents, let date = cal.date(from: comps) {
            due = date
            hasTime = comps.hour != nil
            // Timed reminders are overdue once the time passes; date-only ones after the day ends.
            isOverdue = hasTime ? date < Date() : date < cal.startOfDay(for: Date())
        } else {
            due = nil
            hasTime = false
            isOverdue = false
        }
    }
}

struct RemindersView: View {
    private let manager = EventKitManager.shared
    @State private var items: [ReminderItem] = []

    private var remaining: Int { items.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: 180)                 // fixed module height
        .moduleCard()
        .task(id: "\(manager.remindersAuthorized)-\(manager.changeToken)") {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))   // also catches the midnight rollover
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Reminders")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !manager.remindersAuthorized {
            VStack(spacing: 6) {
                Text("Reminders access needed")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link).font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .light))
                Text("All caught up")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(items) { row($0) }
                }
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 10) {
            Button { toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(item.color)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)

            Spacer(minLength: 8)

            if let label = dueLabel(item) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(item.isOverdue && !item.isCompleted ? Color.red : Color.secondary)
                    .monospacedDigit()
            }
        }
        .opacity(item.isCompleted ? 0.6 : 1)
    }

    private func dueLabel(_ item: ReminderItem) -> String? {
        guard let due = item.due else { return nil }
        if item.isOverdue && !item.isCompleted {
            // Overdue earlier today: show the time. Older: show the date.
            if Calendar.current.isDateInToday(due), item.hasTime {
                return due.formatted(date: .omitted, time: .shortened)
            }
            return due.formatted(.dateTime.month(.abbreviated).day())
        }
        return item.hasTime ? due.formatted(date: .omitted, time: .shortened) : nil
    }

    // MARK: Data

    /// Open items first (overdue, then by due time), completed items last.
    private func sorted(_ list: [ReminderItem]) -> [ReminderItem] {
        func rank(_ i: ReminderItem) -> Int { i.isCompleted ? 2 : (i.isOverdue ? 0 : 1) }
        return list.sorted {
            (rank($0), $0.due ?? .distantFuture) < (rank($1), $1.due ?? .distantFuture)
        }
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        let store = manager.store
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { ReminderItem(reminder: $0) })
            }
        }
    }

    private func load() async {
        guard manager.remindersAuthorized else { items = []; return }
        let store = manager.store
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!

        // Open: due today or earlier (no lower bound catches overdue ones).
        let openPredicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: endOfToday, calendars: nil
        )
        // Done: completed today.
        let donePredicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: startOfToday, ending: endOfToday, calendars: nil
        )

        let open = await fetch(openPredicate)
        let done = await fetch(donePredicate).filter { ($0.due ?? .distantFuture) < endOfToday }
        items = sorted(open + done)
    }

    private func toggle(_ item: ReminderItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newValue = !items[index].isCompleted

        // Update the UI right away; the row slides to its new spot.
        withAnimation(.easeInOut(duration: 0.3)) {
            items[index].isCompleted = newValue
            items = sorted(items)
        }

        Task {
            do {
                guard let reminder = manager.store.calendarItem(withIdentifier: item.id) as? EKReminder else {
                    throw CocoaError(.fileNoSuchFile)
                }
                reminder.isCompleted = newValue
                try manager.store.save(reminder, commit: true)
            } catch {
                print("Couldn't update reminder:", error)
                // Save failed: put the row back the way it was.
                if let i = items.firstIndex(where: { $0.id == item.id }) {
                    withAnimation {
                        items[i].isCompleted = !newValue
                        items = sorted(items)
                    }
                }
            }
        }
    }
}
