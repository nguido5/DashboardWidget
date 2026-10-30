//
//  ModuleCard.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

extension EnvironmentValues {
    /// 1 on the desktop. In full screen the modules are laid out at the larger size directly
    /// (every font, frame, and spacing is multiplied by this), so text and artwork are drawn
    /// at full resolution instead of being magnified like a screenshot.
    @Entry var widgetScale: CGFloat = 1
}

extension View {
    /// Shared subtle panel behind each module, so all four match.
    func moduleCard() -> some View {
        modifier(ModuleCardBackground())
    }
}

private struct ModuleCardBackground: ViewModifier {
    @Environment(\.widgetScale) private var s

    func body(content: Content) -> some View {
        content.background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14 * s, style: .continuous))
    }
}
