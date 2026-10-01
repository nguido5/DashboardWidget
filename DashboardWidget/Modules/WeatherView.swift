//
//  WeatherView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import SwiftUI

struct WeatherView: View {
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
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 148)                 // fixed module height
        .moduleCard()
        .task(id: currentKey) {             // restarts when the city or units change
            while !Task.isCancelled {
                await weather.refresh()
                // Every 15 minutes; retry after a minute if the last attempt failed.
                try? await Task.sleep(for: .seconds(weather.lastAttemptFailed ? 60 : 900))
            }
        }
    }

    private func content(_ snap: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: WeatherCode.symbol(snap.code, isDay: snap.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 34))
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snap.temperature)°")
                        .font(.system(size: 34, weight: .light, design: .rounded))
                    Text(placeName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(WeatherCode.description(snap.code))
                        .font(.system(size: 13, weight: .semibold))
                    Text("H \(snap.high)°  L \(snap.low)°")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Feels like \(snap.feelsLike)°")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().overlay(.white.opacity(0.15))

            HStack(spacing: 0) {
                ForEach(snap.days) { day in
                    VStack(spacing: 2) {
                        Text(day.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: WeatherCode.symbol(day.code))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 14))
                        Text("\(day.high)°/\(day.low)°")
                            .font(.system(size: 11))
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("Offline. Updated \(snap.fetchedAt.formatted(date: .omitted, time: .shortened))")
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 6) {
            Image(systemName: "cloud.slash").font(.system(size: 20, weight: .light))
            Text("Weather unavailable").font(.caption)
            Button("Retry") { Task { await weather.refresh() } }
                .buttonStyle(.link).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
