//
//  ClockView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import SwiftUI

struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 54, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 116)                 // fixed module height
        .moduleCard()
    }
}
