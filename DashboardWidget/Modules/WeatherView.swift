//
//  WeatherView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import SwiftUI

struct WeatherView: View {
    @Environment(\.widgetScale) private var s
    private let weather = WeatherController.shared
    @AppStorage(PrefKey.weatherName) private var placeName = WeatherDefaults.name
    @AppStorage(PrefKey.weatherLat) private var latitude = WeatherDefaults.latitude
    @AppStorage(PrefKey.weatherLon) private var longitude = WeatherDefaults.longitude
    @AppStorage(PrefKey.weatherCelsius) private var celsius = false

    private var currentKey: String {
        WeatherAPI.key(latitude: latitude, longitude: longitude, celsius: celsius)
    }

    var body: some View {
        Group {
            if let snap = weather.snapshot, snap.key == currentKey {
                content(snap)
            } else if weather.lastAttemptFailed {
                unavailable
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14 * s)
        .frame(maxWidth: .infinity)
        .frame(height: WidgetModule.weather.height * s)        // fixed module height
        .moduleCard()
        // Restarts when the city or units change, and pauses while the widget can't be seen.
        .task(id: "\(currentKey)-\(WidgetState.shared.isOnScreen)") {
            guard WidgetState.shared.isOnScreen else { return }
            while !Task.isCancelled {
                // Every 15 minutes (skipped if the data is still fresh); retry after a minute on failure.
                await weather.refresh(ifOlderThan: 900, key: currentKey)
                try? await Task.sleep(for: .seconds(weather.lastAttemptFailed ? 60 : weather.secondsUntilStale(900)))
            }
        }
    }

    private func content(_ snap: WeatherSnapshot) -> some View {
        VStack(spacing: 8 * s) {
            HStack(spacing: 12 * s) {
                Image(systemName: WeatherCode.symbol(snap.code, isDay: snap.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34 * s))
                    .frame(width: 44 * s)

                VStack(alignment: .leading, spacing: 0 * s) {
                    Text("\(snap.temperature)°")
                        .font(.system(size: 34 * s, weight: .light, design: .rounded))
                    Text(placeName)
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8 * s)

                VStack(alignment: .trailing, spacing: 1 * s) {
                    Text(WeatherCode.description(snap.code))
                        .font(.system(size: 13 * s, weight: .semibold))
                    Text("H \(snap.high)°  L \(snap.low)°")
                        .font(.system(size: 12 * s))
                        .foregroundStyle(.secondary)
                    Text("Feels like \(snap.feelsLike)°")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(.white.opacity(0.15))

            HStack(spacing: 0 * s) {
                ForEach(snap.days) { day in
                    VStack(spacing: 2 * s) {
                        Text(day.label)
                            .font(.system(size: 11 * s, weight: .medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: WeatherCode.symbol(day.code))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 14 * s))
                        Text("\(day.high)°/\(day.low)°")
                            .font(.system(size: 11 * s))
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // Showing the last known data because the latest refresh failed.
            if weather.lastAttemptFailed {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.secondary)
                    .help("Offline. Updated \(snap.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 6 * s) {
            Image(systemName: "cloud.slash").font(.system(size: 20 * s, weight: .light))
            Text("Weather unavailable").font(.system(size: 10 * s))
            Button("Retry") { Task { await weather.refresh() } }
                .buttonStyle(.link).font(.system(size: 10 * s))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
