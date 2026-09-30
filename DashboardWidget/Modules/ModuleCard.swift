//
//  ModuleCard.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

extension View {
    /// Shared subtle panel behind each module, so all four match.
    func moduleCard() -> some View {
        background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
