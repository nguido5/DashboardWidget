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

    /// Esc leaves full screen.
    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) {
            toggleFullScreen(nil)
        } else {
            super.cancelOperation(sender)
        }
    }
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: WidgetWindow?
    private let frameName = "DashboardWidgetFrame"
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pinning = false      // true while the widget is being moved onto the current desktop
    private var recheckTask: Task<Void, Never>?
    private var screensAsleep = false

    /// True from the moment full screen is requested until the widget is back to normal.
    private var fullScreenMode = false
    private var frameBeforeFullScreen: NSRect?

    /// Where the widget goes when it has nowhere better to be.
    static let defaultCorner: WidgetCorner = .topLeft

    /// Lets SwiftUI views reach the delegate (the panel asks it to resize when modules change).
    static weak var shared: AppDelegate?

    /// Just above desktop icons, below normal app windows.
    private var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        Task { await EventKitManager.shared.requestAccess() }
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no app menu

        let hosting = NSHostingView(rootView: DashboardView())
        hosting.sizingOptions = [.intrinsicContentSize]   // we size the window ourselves
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
        w.delegate = self

        // Restore the last position; otherwise start in the default corner.
        if w.setFrameUsingName(frameName) {
            // Re-apply the current size (keeps the top-left fixed) so a saved, older size can't clip the panel.
            let topLeft = NSPoint(x: w.frame.minX, y: w.frame.maxY)
            w.setContentSize(size)
            w.setFrameTopLeftPoint(topLeft)
        } else {
            place(w, in: Self.defaultCorner, on: Self.primaryScreen, animated: false)
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
            Task { @MainActor in delegate.screensChanged() }
        })

        // The widget moved (dragged, or placed on another display).
        observers.append(center.addObserver(
            forName: NSWindow.didMoveNotification, object: w, queue: .main
        ) { [weak self] _ in
            guard let delegate = self else { return }
            Task { @MainActor in delegate.refreshDisplays() }
        })

        // Displays asleep, screen locked, or switched to another user: nothing is visible.
        let workspace = NSWorkspace.shared.notificationCenter
        let sleepNames: [Notification.Name] = [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification]
        let wakeNames: [Notification.Name] = [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification]
        for name in sleepNames + wakeNames {
            let asleep = sleepNames.contains(name)
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let delegate = self else { return }
                Task { @MainActor in
                    delegate.screensAsleep = asleep
                    delegate.updateVisibility()
                    if !asleep { delegate.screensChanged() }   // monitors may have reconnected while asleep
                }
            })
        }
        updateVisibility()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    // MARK: Settings

    func applySettings() {
        guard let w = window else { return }
        let defaults = UserDefaults.standard
        let allDesktops = defaults.flag(PrefKey.allDesktops, default: true)
        let onTop = defaults.flag(PrefKey.alwaysOnTop, default: false)
        let hidden = defaults.flag(PrefKey.hidden, default: false)

        // Full screen manages its own level and Space. Hiding leaves full screen first;
        // the hide finishes once the window is back to normal.
        if fullScreenMode {
            if hidden, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
            return
        }

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
        updateVisibility()
    }

    // MARK: Visibility (lets modules pause work nobody can see)

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateVisibility()
    }

    private func updateVisibility() {
        guard let w = window else { return }
        WidgetState.shared.isOnScreen = w.isVisible && w.occlusionState.contains(.visible) && !screensAsleep
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
        guard let w = window, !fullScreenMode else { return }
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
        guard let w = window, !fullScreenMode else { return }
        place(w, in: corner, animated: true)
        applySettings()
    }

    /// Back to the default corner of the main display (the one with the menu bar).
    func resetPosition() {
        UserDefaults.standard.set(false, forKey: PrefKey.hidden)
        guard let w = window, !fullScreenMode else { return }
        place(w, in: Self.defaultCorner, on: Self.primaryScreen, animated: true)
        applySettings()
        refreshDisplays()
    }

    func move(toDisplay id: CGDirectDisplayID) {
        guard let w = window, !fullScreenMode,
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

    /// The display with the menu bar. `NSScreen.main` follows keyboard focus, which is
    /// unreliable while a monitor is being unplugged.
    private static var primaryScreen: NSScreen? { NSScreen.screens.first }

    private func place(_ w: NSWindow, in corner: WidgetCorner, on screen: NSScreen? = nil, animated: Bool) {
        guard let target = screen ?? w.screen ?? Self.primaryScreen else { return }
        let vf = target.visibleFrame                    // excludes menu bar and Dock
        let margin: CGFloat = 24
        let size = w.frame.size
        var x = corner.isLeft ? vf.minX + margin : vf.maxX - size.width - margin
        var y = corner.isTop ? vf.maxY - size.height - margin : vf.minY + margin
        // Small displays: keep the left and top edges on screen rather than the margin.
        x = max(min(x, vf.maxX - size.width), vf.minX)
        y = min(max(y, vf.minY), vf.maxY - size.height)
        w.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: animated)
    }

    /// Which corner of its current screen the widget is closest to (used when switching displays).
    private func nearestCorner(of w: NSWindow) -> WidgetCorner {
        guard let vf = (w.screen ?? Self.primaryScreen)?.visibleFrame else { return Self.defaultCorner }
        let left = w.frame.midX < vf.midX
        let top = w.frame.midY > vf.midY
        switch (left, top) {
        case (true, true): return .topLeft
        case (false, true): return .topRight
        case (true, false): return .bottomLeft
        case (false, false): return .bottomRight
        }
    }

    /// Display setup changed. macOS relocates windows from a removed display on its own,
    /// sometimes a moment after this notification, so check now and again shortly after.
    private func screensChanged() {
        ensureOnScreen()
        refreshDisplays()
        recheckTask?.cancel()
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let delegate = self else { return }
            delegate.ensureOnScreen()
            delegate.refreshDisplays()
        }
    }

    /// If the widget isn't entirely inside one display's usable area (e.g. its monitor was
    /// unplugged and macOS left it hanging off an edge), send it back to the default corner.
    private func ensureOnScreen() {
        guard let w = window, !fullScreenMode else { return }
        let frame = w.frame
        let fits = NSScreen.screens.contains { Self.frame(frame, fitsIn: $0.visibleFrame) }
        if !fits { place(w, in: Self.defaultCorner, on: Self.primaryScreen, animated: false) }
    }

    /// Fully inside `area`. A widget taller than the display only needs its top on screen.
    private static func frame(_ frame: NSRect, fitsIn area: NSRect) -> Bool {
        let slack: CGFloat = 1     // ignore sub-point rounding
        let a = area.insetBy(dx: -slack, dy: -slack)
        let horizontal = frame.minX >= a.minX && frame.maxX <= a.maxX
        let vertical = frame.maxY <= a.maxY && (frame.minY >= a.minY || frame.height > area.height)
        return horizontal && vertical
    }

    // MARK: Full screen

    /// Fills a display in its own Space, with the panel laid out to fit. Defaults to the
    /// display the widget is on; pass one (e.g. a phone extended with OpenDisplay) to go
    /// full screen there. Exiting puts the widget back where it was.
    /// Esc, the menu bar item, or the red/green buttons at the top of the screen exit.
    func toggleFullScreen(on displayID: CGDirectDisplayID? = nil) {
        guard let w = window else { return }
        if fullScreenMode {
            if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
            return
        }

        UserDefaults.standard.set(false, forKey: PrefKey.hidden)
        fullScreenMode = true
        frameBeforeFullScreen = w.frame

        // Native full screen needs a titled, resizable window. The title bar is transparent and
        // only appears when the pointer reaches the top. Like other apps in full screen, it shows
        // a working close button (exits full screen) and a greyed-out minimize button: leaving
        // out .miniaturizable is what makes macOS draw minimize disabled.
        w.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.standardWindowButton(.closeButton)?.isHidden = false
        w.standardWindowButton(.miniaturizeButton)?.isHidden = false

        // macOS takes the window full screen on whichever display it's on, so move it there first.
        var start = frameBeforeFullScreen ?? w.frame
        if let displayID, let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
           screen != w.screen {
            let vf = screen.visibleFrame
            start.origin = NSPoint(x: vf.minX + 24, y: max(vf.maxY - start.height - 24, vf.minY))
        }
        w.setFrame(start, display: false)
        w.collectionBehavior = [.fullScreenPrimary, .managed]
        w.level = .normal

        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        w.toggleFullScreen(nil)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        WidgetState.shared.isFullScreen = true
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        WidgetState.shared.isFullScreen = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        restoreFromFullScreen()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        restoreFromFullScreen()
    }

    /// The close button only appears in full screen; there it means "leave full screen".
    /// The widget itself is never closed (use Hide Widget for that).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.styleMask.contains(.fullScreen) { sender.toggleFullScreen(nil) }
        return false
    }

    private func restoreFromFullScreen() {
        guard let w = window else { return }
        WidgetState.shared.isFullScreen = false
        w.styleMask = [.borderless]
        w.hasShadow = false
        if let frame = frameBeforeFullScreen { w.setFrame(frame, display: true) }
        frameBeforeFullScreen = nil
        fullScreenMode = false
        // Modules may have changed while full screen; fit the panel again.
        if let hosting = w.contentView { resize(to: hosting.fittingSize) }
        applySettings()
        ensureOnScreen()
        refreshDisplays()
    }

    // MARK: Sizing

    /// Fits the window to the panel. A widget in the lower half of the screen keeps its bottom
    /// edge fixed; otherwise the top edge stays put. Never leaves the visible screen area.
    /// Called from SwiftUI while it's laying out the panel. Resizing the window right then
    /// re-enters AppKit layout ("layoutSubtreeIfNeeded on a view which is already being laid out"),
    /// so the resize waits for the current layout pass to finish. Bursts collapse into one.
    func resize(to size: CGSize) {
        let isFirstRequest = pendingSize == nil
        pendingSize = size
        guard isFirstRequest else { return }
        DispatchQueue.main.async { [weak self] in
            guard let delegate = self, let size = delegate.pendingSize else { return }
            delegate.pendingSize = nil
            delegate.applyResize(size)
        }
    }

    private var pendingSize: CGSize?

    private func applyResize(_ size: CGSize) {
        guard let w = window, !fullScreenMode, size.width > 0, size.height > 0 else { return }
        let frame = w.frame
        if abs(frame.width - size.width) < 0.5 && abs(frame.height - size.height) < 0.5 { return }

        let vf = (w.screen ?? Self.primaryScreen)?.visibleFrame ?? frame
        let anchorBottom = frame.midY < vf.midY
        var newFrame = NSRect(
            x: frame.minX,
            y: anchorBottom ? frame.minY : frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if newFrame.maxY > vf.maxY { newFrame.origin.y = vf.maxY - newFrame.height }
        if newFrame.minY < vf.minY && newFrame.height <= vf.height { newFrame.origin.y = vf.minY }
        w.setFrame(newFrame, display: true, animate: false)
    }

    private func refreshDisplays() {
        DisplayStore.shared.refresh(widgetScreen: window?.screen)
    }
}
