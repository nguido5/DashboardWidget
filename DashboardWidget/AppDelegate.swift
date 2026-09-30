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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: WidgetWindow?
    private let frameName = "DashboardWidgetFrame"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon, no app menu
        
        // 1. FIX PERMISSIONS: Silently check access on launch
        Task { await EventKitManager.shared.requestAccess() }

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
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false

        // Just above desktop icons, below normal app windows.
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        // 2. FIX POSITION: Load saved frame first, THEN override it to the left
        w.setFrameAutosaveName(frameName)
        
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            w.setFrameTopLeftPoint(NSPoint(x: vf.minX + 24, y: vf.maxY - 24))
        }

        w.orderFrontRegardless()
        window = w
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }
}
