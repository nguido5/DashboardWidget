//
//  DashboardView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

struct DashboardView: View {
    @AppStorage(PrefKey.liquidGlass) private var liquidGlass = false
    @AppStorage(PrefKey.moduleOrder) private var orderRaw = ""
    @AppStorage(PrefKey.hiddenModules) private var hiddenRaw = ""
    private let state = WidgetState.shared
    private let corner: CGFloat = 24

    private var modules: [WidgetModule] {
        ModuleLayout.visible(orderRaw: orderRaw, hiddenRaw: hiddenRaw)
    }

    var body: some View {
        if state.isFullScreen {
            fullScreen
        } else {
            widget
        }
    }

    // MARK: Normal widget

    private var widget: some View {
        VStack(spacing: 16) {
            if modules.isEmpty {
                emptyMessage
            } else {
                ForEach(modules) { ModuleView(module: $0) }
            }
        }
        .padding(16)
        .frame(width: 320 + 32)                       // 320 content + 16 padding each side
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            AppDelegate.shared?.resize(to: size)      // keep the window fitted as modules change
        }
        .panelStyle(liquidGlass: liquidGlass, corner: corner)
        .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .modifier(WindowDragModifier())               // drag any non-interactive area to move
    }

    private var emptyMessage: some View {
        Text("No modules enabled.\nChoose some from Customize… in the menu bar.")
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
            .frame(width: FullScreenLayout.columnWidth)
    }

    // MARK: Full screen

    /// The panel, laid out in columns that suit the display, scaled up to fill it.
    private var fullScreen: some View {
        GeometryReader { geo in
            let layout = FullScreenLayout.best(for: modules, in: geo.size)
            let s = layout.scale
            // Laid out at the final size (not magnified with scaleEffect, which blurred text).
            HStack(alignment: .top, spacing: FullScreenLayout.spacing * s) {
                if modules.isEmpty {
                    emptyMessage
                } else {
                    ForEach(layout.columns.indices, id: \.self) { index in
                        VStack(spacing: FullScreenLayout.spacing * s) {
                            ForEach(layout.columns[index]) { ModuleView(module: $0) }
                        }
                        .frame(width: FullScreenLayout.columnWidth * s)
                    }
                }
            }
            .padding(FullScreenLayout.padding * s)
            .fixedSize()
            .panelStyle(liquidGlass: liquidGlass, corner: corner * s)
            .environment(\.widgetScale, s)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .bottom) { FullScreenHint() }
    }
}

/// Briefly explains how to leave full screen.
private struct FullScreenHint: View {
    @State private var visible = true

    var body: some View {
        Text("Exit: ✕ at the top of the screen, or Esc")
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 12)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: visible)
            .allowsHitTesting(false)
            .task {
                try? await Task.sleep(for: .seconds(3))
                visible = false
            }
    }
}

struct ModuleView: View {
    let module: WidgetModule

    var body: some View {
        switch module {
        case .clock: ClockView()
        case .weather: WeatherView()
        case .calendar: CalendarView()
        case .reminders: RemindersView()
        case .spotify: SpotifyPlayerView()
        }
    }
}

extension View {
    /// Frosted material (default) or native Liquid Glass.
    @ViewBuilder
    func panelStyle(liquidGlass: Bool, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if liquidGlass {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

/// Moves the widget window when you drag it. Child controls (buttons, the progress bar,
/// clickable text) handle their own gestures first, so they keep working.
struct WindowDragModifier: ViewModifier {
    @State private var startMouse: NSPoint?
    @State private var startOrigin: NSPoint?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    guard let window = NSApp.windows.first(where: { $0 is WidgetWindow }) else { return }
                    let mouse = NSEvent.mouseLocation          // screen coordinates, so the moving window can't skew it
                    if startMouse == nil {
                        startMouse = mouse
                        startOrigin = window.frame.origin
                    }
                    guard let startMouse, let startOrigin else { return }
                    window.setFrameOrigin(NSPoint(
                        x: startOrigin.x + mouse.x - startMouse.x,
                        y: startOrigin.y + mouse.y - startMouse.y
                    ))
                }
                .onEnded { _ in
                    startMouse = nil
                    startOrigin = nil
                }
        )
    }
}
