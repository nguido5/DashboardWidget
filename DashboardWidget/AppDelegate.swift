//
//  AppDelegate.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import AppKit
import SwiftUI

/// Borderless windows refuse key status by default, which breaks clicks/scrolling in some controls.
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum WidgetCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: WidgetWindow?
    private let frameName = "DashboardWidgetFrame"
    private var observers: [NSObjectProtocol] = []
    private var pinning = false      // true while the widget is being moved onto the current desktop

    /// Just above desktop icons, below normal app windows.
    private var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await EventKitManager.shared.requestAccess() }
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no app menu

        let hosting = NSHostingView(rootView: DashboardView())
        let size = hosting.fittingSize

        let w = WidgetWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        w.contentView = hosting
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isMovableByWindowBackground = false   // dragging is handled inside DashboardView
        w.isReleasedWhenClosed = false

        // Restore the last position; otherwise start in the top-left corner.
        if w.setFrameUsingName(frameName) {
            // Re-apply the current size (keeps the top-left fixed) so a saved, older size can't clip the panel.
            let topLeft = NSPoint(x: w.frame.minX, y: w.frame.maxY)
            w.setContentSize(size)
            w.setFrameTopLeftPoint(topLeft)
        } else {
            place(w, in: .topLeft, animated: false)
        }
        w.setFrameAutosaveName(frameName)

        window = w
        ensureOnScreen()
        applySettings()
        refreshDisplays()

        let center = NotificationCenter.default

        // Menu bar settings changed.
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.applySettings() }
        })

        // Monitors plugged in / unplugged / resolution changed.
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in
                delegate.ensureOnScreen()
                delegate.refreshDisplays()
            }
        })

        // The widget moved (dragged, or placed on another display).
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: w, queue: .main
        ) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.refreshDisplays() }
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    // MARK: Settings

    func applySettings() {
        guard let w = window else { return }
        let defaults = UserDefaults.standard
        let allDesktops = defaults.flag(PrefKey.allDesktops, default: true)
        let onTop = defaults.flag(PrefKey.alwaysOnTop, default: false)
        let hidden = defaults.flag(PrefKey.hidden, default: false)

        // While pinning, the window is deliberately free to follow the active desktop.
        var behaviorChanged = false
        if !pinning {
            var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
            if allDesktops { behavior.insert(.canJoinAllSpaces) }
            if w.collectionBehavior != behavior {
                w.collectionBehavior = behavior
                behaviorChanged = true
            }
        }

        let level: NSWindow.Level = onTop ? .floating : desktopLevel
        if w.level != level { w.level = level }

        if hidden {
            if w.isVisible { w.orderOut(nil) }
        } else if !w.isVisible || behaviorChanged {
            w.orderFrontRegardless()
        }
    }

    // MARK: Desktops (Spaces)

    func showOnAllDesktops() {
        UserDefaults.standard.set(true, forKey: PrefKey.allDesktops)
    }

    /// Keeps the widget on the desktop (and display) where the menu was clicked.
    func pinToThisDesktop() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        pin(on: screen)
    }

    private func pin(on screen: NSScreen?) {
        guard let w = window else { return }
        pinning = true

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: PrefKey.allDesktops)
        defaults.set(false, forKey: PrefKey.hidden)

        if let screen, screen != w.screen {
            place(w, in: nearestCorner(of: w), on: screen, animated: false)
        }

        // Pull the widget onto the desktop that's active right now...
        w.collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
        w.orderOut(nil)
        w.orderFrontRegardless()

        // ...then lock it there.
        Task { [self] in
            try? await Task.sleep(for: .milliseconds(200))
            pinning = false
            applySettings()
            refreshDisplays()
        }
    }

    // MARK: Positioning

    func move(to corner: WidgetCorner) {
        UserDefaults.standard.set(false, forKey: PrefKey.hidden)   // moving it also un-hides it
        guard let w = window else { return }
        place(w, in: corner, animated: true)
        applySettings()
    }

    func move(toDisplay id: CGDirectDisplayID) {
        guard let w = window,
              let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { return }
        UserDefaults.standard.set(false, forKey: PrefKey.hidden)

        if UserDefaults.standard.flag(PrefKey.allDesktops, default: true) {
            place(w, in: nearestCorner(of: w), on: screen, animated: true)
            applySettings()
        } else {
            pin(on: screen)     // land on that display's current desktop and stay there
        }
        refreshDisplays()
    }

    private func place(_ w: NSWindow, in corner: WidgetCorner, on screen: NSScreen? = nil, animated: Bool) {
        guard let target = screen ?? w.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = target.visibleFrame                    // excludes menu bar and Dock
        let margin: CGFloat = 24
        let size = w.frame.size
        let x = corner.isLeft ? vf.minX + margin : vf.maxX - size.width - margin
        let y = corner.isTop ? vf.maxY - size.height - margin : vf.minY + margin
        w.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: animated)
    }

    /// Which corner of its current screen the widget is closest to (used when switching displays).
    private func nearestCorner(of w: NSWindow) -> WidgetCorner {
        guard let vf = (w.screen ?? NSScreen.main)?.visibleFrame else { return .topLeft }
        let left = w.frame.midX < vf.midX
        let top = w.frame.midY > vf.midY
        switch (left, top) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    /// If the saved position is no longer on any screen (monitor unplugged), bring it back.
    private func ensureOnScreen() {
        guard let w = window else { return }
        let visible = NSScreen.screens.contains {
            let overlap = $0.visibleFrame.intersection(w.frame)
            return overlap.width > 80 && overlap.height > 80
        }
        if !visible { place(w, in: .topLeft, on: NSScreen.main, animated: false) }
    }

    private func refreshDisplays() {
        DisplayStore.shared.refresh(widgetScreen: window?.screen)
    }
}
