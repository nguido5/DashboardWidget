//
//  SpotifyController.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import AppKit
import Observation

// MARK: - AppleScript bridge (runs off the main thread)

nonisolated struct SpotifySnapshot: Sendable {
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
    let durationMs: Int
    let positionMs: Int
    let isShuffling: Bool
}

nonisolated enum SpotifyResult: Sendable {
    case notRunning
    case denied            // macOS Automation permission missing
    case failed(String)    // anything else, with the real error text
    case state(SpotifySnapshot)
}

nonisolated enum SpotifyBridge {
    private static let queue = DispatchQueue(label: "DashboardWidget.spotify", qos: .userInitiated)

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    private static let stateScript = """
    set stateText to ""
    set trackName to ""
    set artistName to ""
    set albumName to ""
    set artworkAddr to ""
    set trackLengthMs to 0
    set positionMs to 0
    set shuffleOn to false
    tell application "Spotify"
        set stateText to (player state as text)
        try
            set shuffleOn to shuffling
        end try
        try
            set trackName to name of current track
            set artistName to artist of current track
            set trackLengthMs to duration of current track
            set artworkAddr to artwork url of current track
        end try
        try
            set albumName to album of current track
        end try
        try
            set positionMs to round ((player position) * 1000)
        end try
    end tell
    return {stateText, trackName, artistName, albumName, artworkAddr, trackLengthMs, positionMs, shuffleOn}
    """

    /// Compiled once and reused. Only touched on `queue`.
    private nonisolated(unsafe) static var compiledStateScript: NSAppleScript?

    static func fetchState() async -> SpotifyResult {
        // Check first: talking to Spotify while it's closed would launch it.
        guard isRunning else { return .notRunning }

        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                if compiledStateScript == nil {
                    let script = NSAppleScript(source: stateScript)
                    if script?.compileAndReturnError(&error) == true { compiledStateScript = script }
                }
                guard let result = compiledStateScript?.executeAndReturnError(&error) else {
                    let code = (error?["NSAppleScriptErrorNumber"] as? Int) ?? 0
                    let message = (error?["NSAppleScriptErrorMessage"] as? String) ?? "unknown error"
                    print("Spotify AppleScript error \(code): \(message)")
                    switch code {
                    case -1743, -1744: continuation.resume(returning: .denied)
                    case -600:         continuation.resume(returning: .notRunning)
                    default:           continuation.resume(returning: .failed("Error \(code): \(message)"))
                    }
                    return
                }
                let snapshot = SpotifySnapshot(
                    isPlaying: result.atIndex(1)?.stringValue == "playing",
                    title: result.atIndex(2)?.stringValue ?? "",
                    artist: result.atIndex(3)?.stringValue ?? "",
                    album: result.atIndex(4)?.stringValue ?? "",
                    artworkURL: result.atIndex(5)?.stringValue ?? "",
                    durationMs: Int(result.atIndex(6)?.int32Value ?? 0),
                    positionMs: Int(result.atIndex(7)?.int32Value ?? 0),
                    isShuffling: result.atIndex(8)?.booleanValue ?? false
                )
                continuation.resume(returning: .state(snapshot))
            }
        }
    }

    /// command examples: "playpause", "next track", "set player position to 42.5", "set shuffling to true"
    static func send(_ command: String) async {
        guard isRunning else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                var error: NSDictionary?
                _ = NSAppleScript(source: "tell application \"Spotify\" to \(command)")?
                    .executeAndReturnError(&error)
                continuation.resume()
            }
        }
    }
}

// MARK: - Spotify's change announcements

/// Listens for the notice Spotify posts on play, pause, skip, and song change.
/// Uses the selector-based API because only it can ask for immediate delivery.
final class SpotifyAnnouncements: NSObject {
    private var handler: (() -> Void)?

    func start(_ handler: @escaping () -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)),
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        handler = nil
    }

    @objc private func received(_ notification: Notification) {
        handler?()      // delivered on the main thread's run loop
    }
}

// MARK: - Observable state for the view

@MainActor
@Observable
final class SpotifyController {
    static let shared = SpotifyController()

    enum Status { case notRunning, denied, failed, ready }

    var status: Status = .notRunning
    var errorText = ""
    var title = ""
    var artist = ""
    var album = ""
    var artworkURL: URL?
    var isPlaying = false
    var isShuffling = false
    var durationMs = 0
    var positionMs = 0
    var syncedAt = Date()
    
    @ObservationIgnored private var shuffleLockUntil = Date.distantPast
    @ObservationIgnored private var shuffleToken = 0

    @ObservationIgnored private var playLockUntil = Date.distantPast
    @ObservationIgnored private var playToken = 0

    @ObservationIgnored private var seekLockUntil = Date.distantPast
    @ObservationIgnored private var seekToken = 0

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var activeViews = 0     // Spotify cards currently on screen

    private init() {}

    /// Updates come from three places, cheapest first:
    /// 1. Spotify's own play/pause/track-change announcement (instant, costs nothing while idle).
    /// 2. One check just after the current song should end, in case an announcement is missed.
    /// 3. A slow check (every 10 s playing, 30 s paused) for seeks made elsewhere.
    /// Announcements are always handled; the timed checks (2 and 3) pause while the widget
    /// can't be seen, and nothing runs while Spotify is closed.
    func start() {
        // Counted, because switching in or out of full screen rebuilds the Spotify card and
        // SwiftUI may start the new card before stopping the old one. Without the count, the old
        // card's stop() switched updates off for good while the new card was still showing.
        activeViews += 1
        guard !isStarted else { return }
        isStarted = true

        // Spotify's announcements are handled even when the widget is covered: each one is a
        // single quick fetch, and only happens when something actually changed. (Gating these on
        // visibility is what made the widget miss pauses and song changes.)
        // .deliverImmediately: this app is almost never the active app, and macOS may otherwise
        // hold announcements until it is.
        announcements.start {
            SpotifyController.shared.refreshAndReschedule()
        }

        // Spotify opened or quit: resume or end polling.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == "com.spotify.client" else { return }
                Task { @MainActor in SpotifyController.shared.refreshAndReschedule() }
            }))
        }

        refreshAndReschedule()      // one fetch now, even if covered, so the state is current
    }

    func stop() {
        activeViews = max(activeViews - 1, 0)
        guard activeViews == 0, isStarted else { return }
        isStarted = false
        pollTask?.cancel()
        pollTask = nil
        announcements.stop()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
    }

    @ObservationIgnored private let announcements = SpotifyAnnouncements()


    /// Called when the widget becomes visible or hidden.
    func visibilityChanged() {
        guard isStarted else { return }
        restartPolling()
    }

    private func restartPolling() {
        pollTask?.cancel()
        guard isStarted, WidgetState.shared.isOnScreen else { pollTask = nil; return }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                guard let interval = pollInterval else { return }   // wait for Spotify to launch
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Seconds until the next check, or nil to stop polling. While playing, that's whichever
    /// comes first: the slow 10 s check, or just after the current song should end.
    private var pollInterval: Double? {
        switch status {
        case .notRunning:
            return nil
        case .denied, .failed:
            return 30
        case .ready:
            guard isPlaying else { return 30 }
            guard durationMs > 0 else { return 10 }
            let remaining = Double(durationMs) * (1 - progress(at: Date())) / 1000
            // Backup for a missed announcement: one check just after the song should end.
            // The 1 s floor stops a tight loop if Spotify is slow to move on.
            return min(10, max(remaining + 0.5, 1))
        }
    }

    func refresh() async {
        switch await SpotifyBridge.fetchState() {
        case .notRunning:
            status = .notRunning
            isPlaying = false
        case .denied:
            status = .denied
        case .failed(let text):
            status = .failed
            errorText = text
        case .state(let s):
            status = .ready
            title = s.title
            artist = s.artist
            album = s.album
            artworkURL = URL(string: s.artworkURL)
            
            if Date() >= playLockUntil { isPlaying = s.isPlaying }
            if Date() >= shuffleLockUntil { isShuffling = s.isShuffling }
            
            durationMs = s.durationMs
            
            if Date() >= seekLockUntil {
                positionMs = s.positionMs
                syncedAt = Date()
            }
        }
    }

    /// After a user action: refetch now, and if polling is active, re-aim the end-of-song
    /// timer (a seek or skip changes when the current song ends).
    private func refreshAndReschedule() {
        if isStarted && WidgetState.shared.isOnScreen {
            restartPolling()        // refreshes immediately
        } else {
            Task { await refresh() } // keeps the menu bar's Now Playing current
        }
    }

    func progress(at date: Date) -> Double {
        guard durationMs > 0 else { return 0 }
        var position = Double(positionMs)
        if isPlaying { position += date.timeIntervalSince(syncedAt) * 1000 }
        return min(max(position / Double(durationMs), 0), 1)
    }

    // MARK: Controls

    func playPause() {
        positionMs = Int(progress(at: Date()) * Double(durationMs))
        syncedAt = Date()
        isPlaying.toggle()
        
        playToken += 1
        let token = playToken
        playLockUntil = .distantFuture

        Task {
            await SpotifyBridge.send("playpause")
            guard token == playToken else { return }
            playLockUntil = Date().addingTimeInterval(1)
            try? await Task.sleep(for: .seconds(1))
            guard token == playToken else { return }
            playLockUntil = .distantPast
            refreshAndReschedule()
        }
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to fraction: Double) {
        guard durationMs > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        positionMs = Int(clamped * Double(durationMs))
        syncedAt = Date()
        
        seekToken += 1
        let token = seekToken
        seekLockUntil = .distantFuture

        let seconds = Double(positionMs) / 1000
        Task {
            await SpotifyBridge.send("set player position to \(seconds)")
            guard token == seekToken else { return }
            seekLockUntil = Date().addingTimeInterval(1)
            try? await Task.sleep(for: .seconds(1))
            guard token == seekToken else { return }
            seekLockUntil = .distantPast
            refreshAndReschedule()
        }
    }

    func toggleShuffle() {
        isShuffling.toggle()
        let target = isShuffling
        shuffleToken += 1
        let token = shuffleToken
        shuffleLockUntil = .distantFuture

        Task {
            await SpotifyBridge.send("set shuffling to \(target)")
            guard token == shuffleToken else { return }
            shuffleLockUntil = Date().addingTimeInterval(1)
            try? await Task.sleep(for: .seconds(1))
            guard token == shuffleToken else { return }
            shuffleLockUntil = .distantPast
            refreshAndReschedule()
        }
    }

    private func send(_ command: String) {
        Task {
            await SpotifyBridge.send(command)
            refreshAndReschedule()
        }
    }

    func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.open(url)
        }
    }
}
