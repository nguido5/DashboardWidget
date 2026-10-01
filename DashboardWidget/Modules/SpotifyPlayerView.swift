//
//  SpotifyPlayerView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

struct SpotifyPlayerView: View {
    private let spotify = SpotifyController.shared
    @State private var dragFraction: Double?     // set only while scrubbing the bar
    @State private var isHovering = false

    var body: some View {
        Group {
            switch spotify.status {
            case .notRunning:
                message("Spotify isn't running", button: "Open Spotify") { spotify.openSpotify() }
            case .denied:
                message("Allow DashboardWidget to control Spotify", button: "Open Automation Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            case .ready:
                player
            case .failed:
                message(spotify.errorText, button: "Retry") { Task { await spotify.refresh() } }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .frame(height: 120)                 // fixed module height
        .moduleCard()
        .task { spotify.start() }
        .onDisappear { spotify.stop() }
    }

    // MARK: Player

    private var player: some View {
        HStack(spacing: 12) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { spotify.openSpotify() }

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(spotify.title.isEmpty ? "Nothing playing" : spotify.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { spotify.openSpotify() }
                .help("Open Spotify")

                Spacer(minLength: 4)
                progressBar
                Spacer(minLength: 4)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var subtitle: String {
        [spotify.artist, spotify.album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var artwork: some View {
        AsyncImage(url: spotify.artworkURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Seekable progress bar

    private var progressBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = dragFraction ?? spotify.progress(at: context.date)
            let active = isHovering || dragFraction != nil
            GeometryReader { geo in
                let dot: CGFloat = 10
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: max(geo.size.width * fraction, 0))
                    Circle()
                        .fill(.white)
                        .frame(width: dot, height: dot)
                        .shadow(color: .black.opacity(0.25), radius: 2)
                        .offset(x: min(max(geo.size.width * fraction - dot / 2, 0), geo.size.width - dot))
                        .opacity(active ? 1 : 0)
                }
                .frame(height: active ? 6 : 4)                   // bar thickens on hover/drag
                .frame(maxHeight: .infinity)                     // centered inside the taller hit area
                .animation(.easeOut(duration: 0.12), value: active)
                .background(HoverTracker(isHovering: $isHovering))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragFraction = clamp(value.location.x / geo.size.width)
                        }
                        .onEnded { value in
                            spotify.seek(to: clamp(value.location.x / geo.size.width))
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 16)
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            HStack(spacing: 24) {
                Button { spotify.previous() } label: { Image(systemName: "backward.fill") }
                Button { spotify.playPause() } label: {
                    Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                Button { spotify.next() } label: { Image(systemName: "forward.fill") }
            }
            .frame(maxWidth: .infinity)

            HStack {
                Spacer()
                Button { spotify.toggleShuffle() } label: {
                    Image(systemName: "shuffle")
                        .foregroundStyle(spotify.isShuffling ? Color.green : Color.secondary)
                }
                .help(spotify.isShuffling ? "Shuffle on" : "Shuffle off")
            }
        }
        .font(.system(size: 14))
        .buttonStyle(.plain)
    }

    // MARK: Empty states

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note").font(.system(size: 20, weight: .light))
            Text(text).font(.caption)
            Button(button, action: action).buttonStyle(.link).font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hover detection that works even when the app isn't frontmost (SwiftUI's onHover
/// needs the app to be active, and a desktop widget usually isn't).
struct HoverTracker: NSViewRepresentable {
    @Binding var isHovering: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = { isHovering = $0 }
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onChange = { isHovering = $0 }
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never steal clicks
    }
}
