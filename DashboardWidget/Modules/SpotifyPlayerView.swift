//
//  SpotifyPlayerView.swift
//  DashboardWidget
//
//  Created by Nicholas Guido on 9/29/26.
//

import SwiftUI

struct SpotifyPlayerView: View {
    @Environment(\.widgetScale) private var s
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
        .padding(14 * s)
        .frame(maxWidth: .infinity)
        .frame(height: WidgetModule.spotify.height * s)        // fixed module height
        .moduleCard()
        .onAppear { spotify.start() }        // paired one-to-one with onDisappear (start/stop are counted)
        .onDisappear { spotify.stop() }
    }

    // MARK: Player

    private var player: some View {
        HStack(spacing: 12 * s) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { spotify.openSpotify() }

            VStack(alignment: .leading, spacing: 0 * s) {
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(spotify.title.isEmpty ? "Nothing playing" : spotify.title)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12 * s))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { spotify.openSpotify() }
                .help("Open Spotify")

                Spacer(minLength: 4 * s)
                progressBar
                Spacer(minLength: 4 * s)
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
        .frame(width: 64 * s, height: 64 * s)
        .clipShape(RoundedRectangle(cornerRadius: 10 * s, style: .continuous))
    }

    // MARK: Seekable progress bar

    private var progressBar: some View {
        // Ticks once a second only while music is playing and the widget is visible.
        let ticking = spotify.isPlaying && WidgetState.shared.isOnScreen && dragFraction == nil
        return TimelineView(TickSchedule(interval: 1, paused: !ticking)) { _ in
            let fraction = dragFraction ?? spotify.progress(at: Date())
            // Full screen is often a touch screen (a phone via OpenDisplay) with no hover,
            // so the handle stays visible there.
            let active = isHovering || dragFraction != nil || WidgetState.shared.isFullScreen
            GeometryReader { geo in
                let dot: CGFloat = 10 * s
                ZStack(alignment: .leading) {
                    // The fill is a plain rectangle clipped to the track's capsule, so the left
                    // end stays rounded at any progress (a tiny capsule looked like a flat line).
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.18))
                        Rectangle().fill(.white.opacity(0.85))
                            .frame(width: max(geo.size.width * fraction, 0))
                    }
                    .clipShape(Capsule())
                    Circle()
                        .fill(.white)
                        .frame(width: dot, height: dot)
                        .shadow(color: .black.opacity(0.25), radius: 2 * s)
                        .offset(x: min(max(geo.size.width * fraction - dot / 2, 0), geo.size.width - dot))
                        .opacity(active ? 1 : 0)
                }
                .frame(height: (active ? 6 : 4) * s)                   // bar thickens on hover/drag
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
            .frame(height: 16 * s)
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    // MARK: Controls

    private var controls: some View {
        ZStack {
            HStack(spacing: 24 * s) {
                Button { spotify.previous() } label: { Image(systemName: "backward.fill") }
                Button { spotify.playPause() } label: {
                    Image(systemName: spotify.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18 * s))
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
        .font(.system(size: 14 * s))
        .buttonStyle(.plain)
    }

    // MARK: Empty states

    private func message(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6 * s) {
            Image(systemName: "music.note").font(.system(size: 20 * s, weight: .light))
            Text(text).font(.system(size: 10 * s))
            Button(button, action: action).buttonStyle(.link).font(.system(size: 10 * s))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A fixed-interval timeline that can be paused (a paused one draws once and then stops).
struct TickSchedule: TimelineSchedule {
    let interval: TimeInterval
    let paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnyIterator<Date> {
        var next: Date? = startDate
        return AnyIterator {
            defer { next = paused ? nil : next?.addingTimeInterval(interval) }
            return next
        }
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
