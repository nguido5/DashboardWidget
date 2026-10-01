//
//  Weather.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import Foundation
import Observation

// MARK: - Models

nonisolated struct WeatherSnapshot: Sendable {
    struct Day: Identifiable, Sendable {
        let id: String
        let label: String
        let code: Int
        let high: Int
        let low: Int
    }

    let key: String            // which location/units this was fetched for
    let temperature: Int
    let feelsLike: Int
    let code: Int
    let isDay: Bool
    let high: Int
    let low: Int
    let days: [Day]            // the next three days
    let fetchedAt: Date
}

nonisolated struct GeoPlace: Sendable {
    let name: String
    let detail: String         // e.g. "Georgia, United States"
    let latitude: Double
    let longitude: Double
}

// MARK: - WMO weather codes -> text and SF Symbols

nonisolated enum WeatherCode {
    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61: "Light rain"
        case 63: "Rain"
        case 65: "Heavy rain"
        case 66, 67: "Freezing rain"
        case 71: "Light snow"
        case 73: "Snow"
        case 75: "Heavy snow"
        case 77: "Snow grains"
        case 80, 81: "Showers"
        case 82: "Heavy showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm, hail"
        default: "—"
        }
    }

    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 66, 67: "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "questionmark.circle"
        }
    }
}

// MARK: - Open-Meteo client

nonisolated enum WeatherAPI {
    private nonisolated struct ForecastResponse: Decodable {
        nonisolated struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
        }
        nonisolated struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }

    private nonisolated struct GeoResponse: Decodable {
        nonisolated struct Result: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let admin1: String?
            let country: String?
            let country_code: String?
        }
        let results: [Result]?
    }

    static func key(latitude: Double, longitude: Double, celsius: Bool) -> String {
        "\(latitude),\(longitude),\(celsius)"
    }

    static func fetch(latitude: Double, longitude: Double, celsius: Bool) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "temperature_unit", value: celsius ? "celsius" : "fahrenheit"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "4"),      // today + the next 3 days
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }

        let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let daily = decoded.daily
        guard daily.time.count >= 4, daily.weather_code.count >= 4,
              daily.temperature_2m_max.count >= 4, daily.temperature_2m_min.count >= 4 else {
            throw URLError(.cannotParseResponse)
        }

        // Dates arrive as "2026-10-01"; read and print them in UTC so the weekday can't shift.
        let utc = TimeZone(identifier: "UTC")
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = utc
        parser.dateFormat = "yyyy-MM-dd"
        let labeler = DateFormatter()
        labeler.timeZone = utc
        labeler.dateFormat = "EEE"

        let days: [WeatherSnapshot.Day] = (1...3).map { i in
            let label = parser.date(from: daily.time[i]).map { labeler.string(from: $0) } ?? ""
            return WeatherSnapshot.Day(
                id: daily.time[i],
                label: label,
                code: daily.weather_code[i],
                high: Int(daily.temperature_2m_max[i].rounded()),
                low: Int(daily.temperature_2m_min[i].rounded())
            )
        }

        return WeatherSnapshot(
            key: key(latitude: latitude, longitude: longitude, celsius: celsius),
            temperature: Int(decoded.current.temperature_2m.rounded()),
            feelsLike: Int(decoded.current.apparent_temperature.rounded()),
            code: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1,
            high: Int(daily.temperature_2m_max[0].rounded()),
            low: Int(daily.temperature_2m_min[0].rounded()),
            days: days,
            fetchedAt: Date()
        )
    }

    /// "Atlanta" or "Atlanta, Georgia" (the part after the comma picks between same-named cities).
    static func geocode(_ query: String) async throws -> GeoPlace? {
        let parts = query.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let city = parts.first, !city.isEmpty else { return nil }
        let hint = parts.count > 1 ? parts[1].lowercased() : ""

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: city),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let results = try JSONDecoder().decode(GeoResponse.self, from: data).results ?? []

        var match = results.first
        if !hint.isEmpty {
            match = results.first {
                ($0.admin1 ?? "").lowercased().hasPrefix(hint)
                    || ($0.country ?? "").lowercased().hasPrefix(hint)
                    || ($0.country_code ?? "").lowercased() == hint
            } ?? results.first
        }
        guard let place = match else { return nil }

        return GeoPlace(
            name: place.name,
            detail: [place.admin1, place.country].compactMap { $0 }.joined(separator: ", "),
            latitude: place.latitude,
            longitude: place.longitude
        )
    }
}

// MARK: - Observable state for the view

@MainActor
@Observable
final class WeatherController {
    static let shared = WeatherController()

    private(set) var snapshot: WeatherSnapshot?
    private(set) var lastAttemptFailed = false

    private init() {}

    func refresh() async {
        let defaults = UserDefaults.standard
        let latitude = defaults.object(forKey: PrefKey.weatherLat) as? Double ?? WeatherDefaults.latitude
        let longitude = defaults.object(forKey: PrefKey.weatherLon) as? Double ?? WeatherDefaults.longitude
        let celsius = defaults.flag(PrefKey.weatherCelsius, default: false)

        do {
            snapshot = try await WeatherAPI.fetch(latitude: latitude, longitude: longitude, celsius: celsius)
            lastAttemptFailed = false
        } catch {
            if Task.isCancelled { return }
            lastAttemptFailed = true      // keep showing the last good data
        }
    }
}
