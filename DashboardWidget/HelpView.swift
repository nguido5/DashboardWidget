//
//  HelpView.swift
//  DashboardWidget
//

import SwiftUI

/// "DashboardWidget Help" from the menu bar: everything the app can do, in one place.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DashboardWidget").font(.title2.bold())
                    Text("A desktop dashboard that sits just above your wallpaper and below your windows. Everything is controlled from the grid icon in the menu bar.")
                        .foregroundStyle(.secondary)
                }

                section("Modules", icon: "square.grid.2x2", items: [
                    ("Time & Date", "The current time and full date."),
                    ("Weather", "Current conditions, today's high and low, feels-like, and a three-day forecast. Set the city and °F/°C in Customize. Refreshes every 15 minutes; a Wi-Fi-slash icon means you're seeing the last saved forecast."),
                    ("Calendar", "Your next three events. A running event is highlighted with its end time, events within the hour count down (\"in 25 min\"), and clicking one opens it in Calendar. All-day events are optional."),
                    ("Reminders", "Everything due today plus anything overdue (overdue times turn red), grouped into a section per list in the order you choose. Click a circle to complete or un-complete a reminder; click a title to open it in Reminders. Subtasks show their parent reminder in grey to the right."),
                    ("Spotify", "Artwork, track, and artist, with play/pause, previous, next, and shuffle. Hover the progress bar to reveal the handle, then click or drag to seek. Click the artwork or title to open Spotify."),
                ])

                section("Moving and placing the widget", icon: "arrow.up.and.down.and.arrow.left.and.right", items: [
                    ("Drag", "Drag any empty part of the widget to move it."),
                    ("Move to Corner", "Snap it to any corner of its current display."),
                    ("Display", "With more than one monitor, send it to another display."),
                    ("Reset Position", "Puts it back in the top-left corner of your main display."),
                    ("Unplugged monitors", "If a display disappears, or the widget ends up partly off screen, it returns to the top-left corner of your main display automatically."),
                ])

                section("Full screen", icon: "arrow.up.left.and.arrow.down.right", items: [
                    ("Enter Full Screen", "Fills the widget's current display in its own Space, with the modules arranged in columns and drawn at full resolution to fit."),
                    ("Full Screen On", "With more than one display, go full screen directly on another one, such as a phone or iPad extended with OpenDisplay. When you exit, the widget returns to where it was."),
                    ("Leaving full screen", "Move the pointer to the top of the screen and click the close (✕) or green button, press Esc, or choose Exit Full Screen from the menu bar icon. On a touch screen, the Spotify progress handle stays visible so you can drag it."),
                ])

                section("Desktops and layering", icon: "rectangle.stack", items: [
                    ("Show on All Desktops", "The widget follows you to every desktop (Space)."),
                    ("Pin to This Desktop", "Keeps it only on the desktop where you chose the command."),
                    ("Float Above Other Windows", "Keeps it on top of app windows instead of behind them."),
                    ("Hide / Show Widget", "Hides it without quitting. Moving it to a corner or display also shows it again."),
                ])

                section("Menu bar shortcuts", icon: "menubar.rectangle", items: [
                    ("Modules", "Turn individual modules on or off without opening Customize."),
                    ("Spotify", "See what's playing and control playback from the menu bar."),
                    ("Open", "Jump to Calendar, Reminders, or Spotify."),
                    ("Refresh Now", "Re-fetch weather, events, reminders, and Spotify immediately."),
                ])

                section("Customize", icon: "slider.horizontal.3", items: [
                    ("Modules", "Drag to reorder, uncheck to hide."),
                    ("Weather", "Search for a city (add a state or country to pick between same-named places) and choose Celsius."),
                    ("Reminders", "Set the order of your lists. Lists you name always get a section, even when nothing is due; other lists appear only when they have something due. You can also turn the parent-reminder labels off."),
                    ("Style", "Liquid Glass Style swaps the frosted panel for macOS's glass material."),
                ])

                section("Battery", icon: "leaf", items: [
                    ("Idle when unseen", "When the widget is hidden, covered by other windows, or your displays are asleep, Spotify and weather updates pause."),
                    ("Event-driven updates", "Calendar and Reminders refresh when something changes instead of on a timer. Spotify updates come from Spotify's own play/pause/track notifications, with only a slow background check."),
                ])

                section("Permissions", icon: "lock", items: [
                    ("Calendar and Reminders", "Needed to show events and reminders. Change in System Settings › Privacy & Security."),
                    ("Automation (Spotify)", "Needed to read and control playback. Change in System Settings › Privacy & Security › Automation."),
                    ("Launch at Login", "Turn on from the menu. If macOS asks, approve it in Login Items settings."),
                ])

                Text("Weather data by Open-Meteo.com")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 620)
    }

    private func section(_ title: String, icon: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ForEach(items, id: \.0) { name, detail in
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).fontWeight(.medium)
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
