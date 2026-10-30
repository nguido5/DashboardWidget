//
//  RemindersView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI
import EventKit

extension PrefKey {
    static let reminderListOrder = "reminderListOrder"
    static let reminderShowNamedLists = "reminderShowNamedLists"
    static let reminderShowParents = "reminderShowParents"
}

enum RemindersDefaults {
    static let listOrder = "Recruiting, Academic, Personal"
}

/// Plain, thread-safe snapshot of a reminder (EKReminder itself can't cross threads safely).
nonisolated struct ReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let hasTime: Bool
    let isOverdue: Bool
    let color: Color
    let listName: String
    /// Title of the reminder this one is a subtask of, if any.
    let parentTitle: String?
    var isCompleted: Bool

    init(reminder: EKReminder, parentTitle: String?) {
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? "Untitled"
        color = Color(nsColor: reminder.calendar?.color ?? .systemBlue)   // the list's color
        listName = reminder.calendar?.title ?? ""
        isCompleted = reminder.isCompleted
        self.parentTitle = parentTitle

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

/// Subtask -> parent links. EventKit has no public API for subtasks, so this reads the
/// reminder's private `parentID` and matches it against other reminders' `objectID`
/// (EKObjectID implements isEqual/hash, so the IDs work as dictionary keys).
/// Every call is guarded: if Apple doesn't fill these in, parents simply don't show.
nonisolated enum ReminderHierarchy {
    private static let parentSelector = NSSelectorFromString("parentID")
    private static let objectSelector = NSSelectorFromString("objectID")

    static func key(of reminder: EKReminder) -> NSObject? {
        id(from: reminder, selector: objectSelector)
    }

    static func parentKey(of reminder: EKReminder) -> NSObject? {
        id(from: reminder, selector: parentSelector)
    }

    private static func id(from reminder: EKReminder, selector: Selector) -> NSObject? {
        guard reminder.responds(to: selector) else { return nil }
        return reminder.perform(selector)?.takeUnretainedValue() as? NSObject
    }
}

struct ReminderGroup: Identifiable {
    let id: String
    let name: String
    let color: Color
    let items: [ReminderItem]

    var remaining: Int { items.filter { !$0.isCompleted }.count }
}

/// A reminder list, for sections that have nothing due.
struct ReminderListInfo: Equatable {
    let name: String
    let color: Color
}

struct RemindersView: View {
    @Environment(\.widgetScale) private var s
    private let manager = EventKitManager.shared
    @AppStorage(PrefKey.reminderListOrder) private var listOrder = RemindersDefaults.listOrder
    @AppStorage(PrefKey.reminderShowNamedLists) private var showNamedLists = true
    @AppStorage(PrefKey.reminderShowParents) private var showParents = true
    @State private var items: [ReminderItem] = []
    @State private var lists: [ReminderListInfo] = []

    private var remaining: Int { items.filter { !$0.isCompleted }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            header
            content
        }
        .padding(14 * s)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: WidgetModule.reminders.height * s)      // fixed module height
        .moduleCard()
        .task(id: "\(manager.remindersAuthorized)-\(manager.changeToken)") {
            // Reloads on any Reminders change (and at midnight, via changeToken). Otherwise it
            // only wakes when a timed reminder becomes overdue, so it's idle most of the time.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(secondsUntilNextOverdue()))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Reminders")
                .font(.system(size: 13 * s, weight: .semibold))
            Spacer()
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !manager.remindersAuthorized {
            VStack(spacing: 6 * s) {
                Text("Reminders access needed")
                    .font(.system(size: 10 * s)).foregroundStyle(.secondary)
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link).font(.system(size: 10 * s))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 4 * s) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22 * s, weight: .light))
                Text("All caught up")
                    .font(.system(size: 10 * s))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10 * s) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6 * s) {
                            groupHeader(group)
                            ForEach(group.items) { row($0) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func groupHeader(_ group: ReminderGroup) -> some View {
        HStack(spacing: 6 * s) {
            Circle().fill(group.color).frame(width: 6 * s, height: 6 * s)
            Text(group.name)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if group.items.isEmpty {
                Text("Nothing due")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.tertiary)
            } else if group.remaining > 0 {
                Text("\(group.remaining)")
                    .font(.system(size: 11 * s))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func row(_ item: ReminderItem) -> some View {
        HStack(spacing: 10 * s) {
            Button { toggle(item) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17 * s))
                    .foregroundStyle(item.color)
            }
            .buttonStyle(.plain)

            // Title first; the parent (if any) sits to its right on the same line, dimmed,
            // and is the first thing to shrink when space runs out.
            HStack(spacing: 6 * s) {
                Text(item.title)
                    .font(.system(size: 13 * s))
                    .lineLimit(1)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .layoutPriority(1)

                if showParents, let parent = item.parentTitle {
                    Text(parent)
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(minWidth: 36 * s, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { openInReminders(item) }
            .help(item.parentTitle.map { "Subtask of \($0). Click to open in Reminders" } ?? "Open in Reminders")

            if let label = dueLabel(item) {
                Text(label)
                    .font(.system(size: 11 * s))
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

    private func openInReminders(_ item: ReminderItem) {
        AppLinks.open("x-apple-reminderkit://REMCDReminder/\(item.id)", fallbackApp: AppLinks.remindersApp)
    }

    // MARK: Grouping

    /// The names from the Customize window, lowercased, in order.
    private var preferredOrder: [String] {
        listOrder.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Position of a list in the preferred order, matched loosely ("academic" matches "Academics").
    private func rank(of listName: String, in preferred: [String]) -> Int? {
        let name = listName.lowercased()
        guard !name.isEmpty else { return nil }
        return preferred.firstIndex { name == $0 || name.hasPrefix($0) || $0.hasPrefix(name) }
    }

    /// One section per list: your listed order first, any other lists after (A-Z).
    /// Lists named in Customize always get a section (optional); others only when something is due.
    /// `items` is already sorted (open first, completed last), and grouping keeps that order.
    private var groups: [ReminderGroup] {
        let preferred = preferredOrder
        var byList = Dictionary(grouping: items, by: \.listName)
        if showNamedLists {
            for list in lists where byList[list.name] == nil && rank(of: list.name, in: preferred) != nil {
                byList[list.name] = []
            }
        }
        let colors = Dictionary(lists.map { ($0.name, $0.color) }, uniquingKeysWith: { first, _ in first })
        return byList
            .map { name, list in
                ReminderGroup(
                    id: name,
                    name: name.isEmpty ? "Reminders" : name,
                    color: list.first?.color ?? colors[name] ?? Color.secondary,
                    items: list
                )
            }
            .sorted { a, b in
                let ra = rank(of: a.id, in: preferred) ?? Int.max
                let rb = rank(of: b.id, in: preferred) ?? Int.max
                if ra != rb { return ra < rb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    // MARK: Data

    /// Open items first (overdue, then by due time), completed items last.
    private func sorted(_ list: [ReminderItem]) -> [ReminderItem] {
        func rank(_ i: ReminderItem) -> Int { i.isCompleted ? 2 : (i.isOverdue ? 0 : 1) }
        return list.sorted {
            (rank($0), $0.due ?? .distantFuture) < (rank($1), $1.due ?? .distantFuture)
        }
    }

    /// How long until the next open, timed reminder turns overdue (red). Capped at an hour.
    private func secondsUntilNextOverdue() -> Double {
        let now = Date()
        let next = items
            .filter { !$0.isCompleted && !$0.isOverdue && $0.hasTime }
            .compactMap(\.due)
            .filter { $0 > now }
            .min()
        guard let next else { return 3600 }
        return min(max(next.timeIntervalSince(now) + 1, 1), 3600)
    }

    private static func fetch(_ store: EKEventStore, _ predicate: NSPredicate) async -> [EKReminder] {
        // EKReminder isn't Sendable; the array is only handed from EventKit's queue to here.
        nonisolated(unsafe) var result: [EKReminder] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                result = reminders ?? []
                continuation.resume()
            }
        }
        return result
    }

    private func load() async {
        guard manager.remindersAuthorized else { items = []; lists = []; return }
        let store = manager.store
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!

        let latestLists = store.calendars(for: .reminder).map {
            ReminderListInfo(name: $0.title, color: Color(nsColor: $0.color ?? .systemBlue))
        }
        if latestLists != lists { lists = latestLists }

        // All open reminders (parents are often undated, so they're needed for titles),
        // plus everything completed today.
        let open = await Self.fetch(store, store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        ))
        let done = await Self.fetch(store, store.predicateForCompletedReminders(
            withCompletionDateStarting: startOfToday, ending: endOfToday, calendars: nil
        ))

        var titles: [NSObject: String] = [:]
        for reminder in open + done {
            if let key = ReminderHierarchy.key(of: reminder) { titles[key] = reminder.title ?? "Untitled" }
        }
        func item(_ reminder: EKReminder) -> ReminderItem {
            let parent = ReminderHierarchy.parentKey(of: reminder).flatMap { titles[$0] }
            return ReminderItem(reminder: reminder, parentTitle: parent)
        }

        // Shown: open ones due today or earlier, and ones completed today that were due by today.
        let dueOpen = open.filter { reminder in
            guard let comps = reminder.dueDateComponents, let date = cal.date(from: comps) else { return false }
            return date < endOfToday
        }
        let shown = dueOpen.map(item) + done.map(item).filter { ($0.due ?? .distantFuture) < endOfToday }
        items = sorted(shown)
    }

    private func toggle(_ item: ReminderItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newValue = !items[index].isCompleted

        // Update the UI right away; the row slides to its new spot within its list.
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
