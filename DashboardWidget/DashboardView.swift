//
//  DashboardView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

struct DashboardView: View {
    private let corner: CGFloat = 24

    var body: some View {
        VStack(spacing: 16) {
            TimeCalendarView()
            RemindersView()
            SpotifyPlayerView()
        }
        .padding(16)
        .frame(width: 320 + 32)   // 320 content + 16 padding each side
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        )
    }

    private func placeholder(_ title: String, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.06))
            .frame(height: height)
            .overlay(Text(title).font(.headline).foregroundStyle(.secondary))
    }
}
