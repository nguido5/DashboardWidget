//
//  ClockView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import SwiftUI

struct ClockView: View {
    @Environment(\.widgetScale) private var s
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(spacing: 2 * s) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 54 * s, weight: .thin, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 14 * s, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14 * s)
        .frame(maxWidth: .infinity)
        .frame(height: WidgetModule.clock.height * s)          // fixed module height
        .moduleCard()
    }
}
