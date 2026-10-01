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
    @State private var login = LoginItemStore()
    private let displayStore = DisplayStore.shared

    var body: some Scene {
        MenuBarExtra("Dashboard", systemImage: "square.grid.2x2") {
            Button(hidden ? "Show Widget" : "Hide Widget") { hidden.toggle() }

            Menu("Move to Corner") {
                ForEach(WidgetCorner.allCases) { corner in
                    Button(corner.title) { appDelegate.move(to: corner) }
                }
            }

            if displayStore.displays.count > 1 {
                Menu("Display") {
                    ForEach(displayStore.displays) { display in
                        Toggle(display.name, isOn: Binding(
                            get: { displayStore.currentID == display.id },
                            set: { _ in appDelegate.move(toDisplay: display.id) }
                        ))
                    }
                }
            }

            Divider()
            Toggle("Show on All Desktops", isOn: Binding(
                get: { allDesktops },
                set: { $0 ? appDelegate.showOnAllDesktops() : appDelegate.pinToThisDesktop() }
            ))
            Button("Pin to This Desktop") { appDelegate.pinToThisDesktop() }
            Toggle("Float Above Other Windows", isOn: $alwaysOnTop)

            Divider()
            CustomizeMenuButton()
            Toggle("Include All-Day Events", isOn: $includeAllDay)
            Toggle("Liquid Glass Style", isOn: $liquidGlass)

            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { login.isEnabled },
                set: { login.set($0) }
            ))
            if login.needsApproval {
                Button("Approve in Login Items Settings…") { login.openSettings() }
            }

            Divider()
            Button("Quit DashboardWidget") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }

        Window("Customize Widget", id: "customize") {
            CustomizeView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)     // only opens when you choose Customize…
        .restorationBehavior(.disabled)
    }
}

/// Needs its own view to reach the openWindow action.
private struct CustomizeMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Customize…") {
            openWindow(id: "customize")
            NSApp.activate()
        }
    }
}
