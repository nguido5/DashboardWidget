//
//  CustomizeView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import SwiftUI

struct CustomizeView: View {
    @AppStorage(PrefKey.moduleOrder) private var orderRaw = ""
    @AppStorage(PrefKey.hiddenModules) private var hiddenRaw = ""
    @AppStorage(PrefKey.weatherName) private var weatherName = WeatherDefaults.name
    @AppStorage(PrefKey.weatherLat) private var weatherLat = WeatherDefaults.latitude
    @AppStorage(PrefKey.weatherLon) private var weatherLon = WeatherDefaults.longitude
    @AppStorage(PrefKey.weatherCelsius) private var celsius = false
    @AppStorage(PrefKey.reminderListOrder) private var reminderListOrder = RemindersDefaults.listOrder

    @State private var query = ""
    @State private var status: String?
    @State private var searching = false

    private var order: [WidgetModule] { ModuleLayout.order(from: orderRaw) }
    private var hidden: Set<WidgetModule> { ModuleLayout.hidden(from: hiddenRaw) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            modulesSection
            weatherSection
            remindersSection
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 430)
    }

    // MARK: Modules

    private var modulesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modules").font(.headline)
            Text("Drag to reorder. Uncheck to hide.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(order) { module in
                    Toggle(module.title, isOn: visibility(of: module))
                }
                .onMove(perform: move)
            }
            .listStyle(.bordered)
            .frame(height: 190)
        }
    }

    // MARK: Weather

    private var weatherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weather").font(.headline)
            HStack(spacing: 4) {
                Text("Location:").foregroundStyle(.secondary)
                Text(weatherName).fontWeight(.medium)
            }
            HStack {
                TextField("City, e.g. Atlanta or Atlanta, Georgia", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(search)
                Button("Set") { search() }
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Use Celsius", isOn: $celsius)
            Text("Weather data by Open-Meteo.com")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reminders").font(.headline)
            Text("List order, top to bottom (comma-separated)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Recruiting, Academic, Personal", text: $reminderListOrder)
                .textFieldStyle(.roundedBorder)
            Text("Lists you don't name appear after these, A–Z. Names match loosely, so “Academic” also matches “Academics”.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func visibility(of module: WidgetModule) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(module) },
            set: { show in
                var set = hidden
                if show { set.remove(module) } else { set.insert(module) }
                hiddenRaw = ModuleLayout.serialize(set)
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = order
        list.move(fromOffsets: source, toOffset: destination)
        orderRaw = ModuleLayout.serialize(list)
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !searching else { return }
        searching = true
        status = nil

        Task {
            do {
                if let place = try await WeatherAPI.geocode(text) {
                    weatherName = place.name
                    weatherLat = place.latitude
                    weatherLon = place.longitude
                    status = "Set to \(place.name)" + (place.detail.isEmpty ? "" : " (\(place.detail))")
                    query = ""
                } else {
                    status = "Couldn't find “\(text)”. Try adding a state or country."
                }
            } catch {
                status = "Search failed. Check your connection and try again."
            }
            searching = false
        }
    }
}
