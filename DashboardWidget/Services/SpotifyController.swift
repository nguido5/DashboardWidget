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

    static func fetchState() async -> SpotifyResult {
        // Check first: talking to Spotify while it's closed would launch it.
        guard isRunning else { return .notRunning }

        return await withCheckedContinuation { continuation in
            queue.async {
                var error: NSDictionary?
                guard let result = NSAppleScript(source: stateScript)?.executeAndReturnError(&error) else {
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
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard pollTask == nil else { return }

        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await SpotifyController.shared.refresh() }
        }

        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    
    func stop() {
        pollTask?.cancel()
        pollTask = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
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
            await refresh()
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
            await refresh()
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
            await refresh()
        }
    }

    private func send(_ command: String) {
        Task {
            await SpotifyBridge.send(command)
            await refresh()
        }
    }

    func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.open(url)
        }
    }
}
