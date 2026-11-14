import SwiftUI
import AVKit
import Photos

/// Handles video playback on the active triage card (PRD Section 3.1 & Section 7):
/// - Autoplays muted in a continuous loop.
/// - Displays a compact scrubber bar at the bottom of the card.
/// - Long-press (or 2x pill) scrubs/plays video previews at 2.0x speed.
/// - Floating speaker button toggles audio for the session.
public struct LivePhotoVideoPlayerView: View {
    public let asset: MediaAsset
    @Binding public var isAudioMuted: Bool

    @State private var player: AVPlayer?
    @State private var isDownloadingFromiCloud = false
    @State private var isFastForwarding2x = false
    @State private var currentProgress: Double = 0.0
    @State private var durationSeconds: Double = 1.0
    @State private var timeObserverToken: Any?

    public init(asset: MediaAsset, isAudioMuted: Binding<Bool>) {
        self.asset = asset
        self._isAudioMuted = isAudioMuted
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if let player {
                VideoPlayer(player: player)
                    .disabled(true) // Let parent card handle swipe/tap/long-press gestures cleanly
                    .onAppear {
                        player.isMuted = isAudioMuted
                        player.play()
                    }
                    .onChange(of: isAudioMuted) { _, muted in
                        player.isMuted = muted
                    }
            } else {
                Color.clear
            }

            // Top-right iCloud streaming badge or 2x speed pill
            VStack {
                HStack {
                    if isFastForwarding2x {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                            Text("2.0×")
                        }
                        .exifMonoStyle(size: 12, color: SwipeDeckTheme.accentUndo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    if isDownloadingFromiCloud {
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.75)
                            Image(systemName: "icloud.and.arrow.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(14)

                Spacer()

                // Bottom Scrubber + Floating Audio Speaker Toggle
                HStack(spacing: 12) {
                    // Muted/Unmuted speaker toggle (PRD Section 7)
                    Button {
                        HapticEngine.shared.fireSelectionTick()
                        isAudioMuted.toggle()
                    } label: {
                        Image(systemName: isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)

                    // Visible progress scrubber bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 5)
                            Capsule()
                                .fill(Color.white)
                                .frame(width: max(0, geo.size.width * currentProgress), height: 5)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 20)

                    if let durationText = asset.formattedDuration {
                        Text(durationText)
                            .exifMonoStyle(size: 11, color: SwipeDeckTheme.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .onLongPressGesture(minimumDuration: 0.25, pressing: { isPressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isFastForwarding2x = isPressing
            }
            player?.rate = isPressing ? 2.0 : 1.0
        }, perform: {})
        .task(id: asset.id) {
            loadVideo()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    private func loadVideo() {
        cleanupPlayer()
        AssetPrefetchPipeline.shared.requestVideoPlayerItem(for: asset.id) { item, inCloud in
            self.isDownloadingFromiCloud = inCloud
            guard let item else { return }

            let avPlayer = AVPlayer(playerItem: item)
            avPlayer.isMuted = isAudioMuted
            avPlayer.actionAtItemEnd = .none

            // Loop video automatically
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                avPlayer.seek(to: .zero)
                avPlayer.play()
            }

            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            let token = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                let currentSec = CMTimeGetSeconds(time)
                let totalSec = max(1.0, asset.duration)
                if currentSec.isFinite {
                    self.currentProgress = min(1.0, max(0.0, currentSec / totalSec))
                }
            }

            self.timeObserverToken = token
            self.player = avPlayer
            avPlayer.play()
        }
    }

    private func cleanupPlayer() {
        if let token = timeObserverToken, let player {
            player.removeTimeObserver(token)
        }
        timeObserverToken = nil
        player?.pause()
        player = nil
    }
}
