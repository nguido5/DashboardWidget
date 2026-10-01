//
//  LoginItemStore.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/30/26.
//

import ServiceManagement
import Observation

@MainActor
@Observable
final class LoginItemStore {
    private(set) var isEnabled = false
    private(set) var needsApproval = false

    init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = (status == .enabled)
        needsApproval = (status == .requiresApproval)
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            print("Launch at login error:", error)
        }
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
