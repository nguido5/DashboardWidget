//
//  DashboardWidgetApp.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

@main
struct DashboardWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage(PrefKey.allDesktops) private var allDesktops = true
    @AppStorage(PrefKey.alwaysOnTop) private var alwaysOnTop = false
    @AppStorage(PrefKey.hidden) private var hidden = false
    @AppStorage(PrefKey.includeAllDay) private var includeAllDay = false
    @AppStorage(PrefKey.liquidGlass) private var liquidGlass = false
    @AppStorage(PrefKey.weatherCelsius) private var celsius = false
    @AppStorage(PrefKey.reminderShowParents) private var showParents = true
    @AppStorage(PrefKey.moduleOrder) private var orderRaw = ""
    @AppStorage(PrefKey.hiddenModules) private var hiddenRaw = ""
    @State private var login = LoginItemStore()
    private let displayStore = DisplayStore.shared
    private let state = WidgetState.shared
    private let spotify = SpotifyController.shared

    var body: some Scene {
        MenuBarExtra("Dashboard", systemImage: "square.grid.2x2") {
            // Widget
            Button(hidden ? "Show Widget" : "Hide Widget") { hidden.toggle() }
                .keyboardShortcut("h")
            Button(state.isFullScreen ? "Exit Full Screen" : "Enter Full Screen") {
                appDelegate.toggleFullScreen()
            }
            .keyboardShortcut("f", modifiers: [.control, .command])
            if !state.isFullScreen, displayStore.displays.count > 1 {
                // Straight to another screen, e.g. a phone or iPad extended with OpenDisplay.
                Menu("Full Screen On") {
                    ForEach(displayStore.displays) { display in
                        Button(display.name) { appDelegate.toggleFullScreen(on: display.id) }
                    }
                }
            }
            Button("Refresh Now") { AppActions.refreshAll() }
                .keyboardShortcut("r")

            Divider()
            modulesMenu
            Menu("Position") {
                ForEach(WidgetCorner.allCases) { corner in
                    Button(corner.title) { appDelegate.move(to: corner) }
                }
                Divider()
                Button("Reset to Default Position") { appDelegate.resetPosition() }
            }
            .disabled(state.isFullScreen)

            if displayStore.displays.count > 1 {
                Menu("Display") {
                    ForEach(displayStore.displays) { display in
                        Toggle(display.name, isOn: Binding(
                            get: { displayStore.currentID == display.id },
                            set: { _ in appDelegate.move(toDisplay: display.id) }
                        ))
                    }
                }
                .disabled(state.isFullScreen)
            }

            Divider()
            Toggle("Show on All Desktops", isOn: Binding(
                get: { allDesktops },
                set: { $0 ? appDelegate.showOnAllDesktops() : appDelegate.pinToThisDesktop() }
            ))
            .disabled(state.isFullScreen)
            Button("Pin to This Desktop") { appDelegate.pinToThisDesktop() }
                .disabled(state.isFullScreen)
            Toggle("Float Above Other Windows", isOn: $alwaysOnTop)
                .disabled(state.isFullScreen)

            Divider()
            spotifyMenu
            Menu("Open") {
                Button("Calendar") { AppLinks.openApp(AppLinks.calendarApp) }
                Button("Reminders") { AppLinks.openApp(AppLinks.remindersApp) }
                Button("Spotify") { spotify.openSpotify() }
            }

            Divider()
            OpenWindowButton(title: "Customize…", id: "customize")
                .keyboardShortcut(",")
            Menu("Options") {
                Toggle("Include All-Day Events", isOn: $includeAllDay)
                Toggle("Show Parent Reminders", isOn: $showParents)
                Toggle("Use Celsius", isOn: $celsius)
                Toggle("Liquid Glass Style", isOn: $liquidGlass)
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { login.isEnabled },
                set: { login.set($0) }
            ))
            if login.needsApproval {
                Button("Approve in Login Items Settings…") { login.openSettings() }
            }

            Divider()
            OpenWindowButton(title: "DashboardWidget Help", id: "help")
                .keyboardShortcut("?")
            Button("About DashboardWidget") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Button("Quit DashboardWidget") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Window("Customize Widget", id: "customize") {
            CustomizeView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)     // only opens when you choose Customize…
        .restorationBehavior(.disabled)

        Window("DashboardWidget Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            // Point the standard Help menu at our help window instead of "Help isn't available".
            CommandGroup(replacing: .help) {
                OpenWindowButton(title: "DashboardWidget Help", id: "help")
                    .keyboardShortcut("?")
            }
        }
    }

    // MARK: Submenus

    private var modulesMenu: some View {
        let hiddenSet = ModuleLayout.hidden(from: hiddenRaw)
        return Menu("Modules") {
            ForEach(ModuleLayout.order(from: orderRaw)) { module in
                Toggle(module.title, isOn: Binding(
                    get: { !hiddenSet.contains(module) },
                    set: { show in
                        var set = hiddenSet
                        if show { set.remove(module) } else { set.insert(module) }
                        hiddenRaw = ModuleLayout.serialize(set)
                    }
                ))
            }
        }
    }

    @ViewBuilder
    private var spotifyMenu: some View {
        Menu("Spotify") {
            if spotify.status == .ready, !spotify.title.isEmpty {
                Text(spotify.title)
                if !spotify.artist.isEmpty { Text(spotify.artist) }
                Divider()
            }
            Button("Play / Pause") { spotify.playPause() }
            Button("Next Track") { spotify.next() }
            Button("Previous Track") { spotify.previous() }
            Toggle("Shuffle", isOn: Binding(
                get: { spotify.isShuffling },
                set: { _ in spotify.toggleShuffle() }
            ))
            Divider()
            Button("Open Spotify") { spotify.openSpotify() }
        }
    }
}

/// Needs its own view to reach the openWindow action.
private struct OpenWindowButton: View {
    let title: String
    let id: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) {
            openWindow(id: id)
            NSApp.activate()
        }
    }
}
