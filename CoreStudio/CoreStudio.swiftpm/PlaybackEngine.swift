import Foundation
import AVFoundation
import Combine

final class PlaybackEngine: ObservableObject {
    @Published var player: AVPlayer = AVPlayer()
    @Published var isPlaying: Bool = false

    var onTimeChanged: ((Double) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?
    
    private var composition: AVMutableComposition?
    private var videoComposition: AVVideoComposition?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var currentRate: Float = 0.0
    /// True while a rebuilt timeline is being put back at the playhead; time updates are ignored meanwhile.
    private var restoringTime = false

    init() {
        setupObservers()
    }

    deinit {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
    }

    private func setupObservers() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, !self.restoringTime else { return }
            self.onTimeChanged?(time.seconds)
        }
        
        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                let playing = player.timeControlStatus == .playing
                self?.isPlaying = playing
                self?.onStatusChanged?(playing)
            }
        }
    }

    // MARK: - JKL Transport Controls
    func jklForward() {
        currentRate = currentRate <= 0 ? 1.0 : min(currentRate * 2.0, 8.0)
        player.rate = currentRate
    }

    func jklReverse() {
        currentRate = currentRate >= 0 ? -1.0 : max(currentRate * 2.0, -8.0)
        player.rate = currentRate
    }

    func jklStop() {
        currentRate = 0.0
        player.pause()
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            jklStop()
        } else {
            jklForward()
        }
    }

    func step(frames: Int, fps: Double) {
        player.pause()
        currentRate = 0.0
        let seconds = Double(frames) / fps
        let newTime = max(0, player.currentTime().seconds + seconds)
        seek(to: newTime)
    }

    func seek(to timeInSeconds: Double) {
        let cmTime = CMTime(seconds: timeInSeconds, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// The last built timeline, for export.
    func exportAssets() -> (AVComposition, AVVideoComposition?)? {
        guard let composition else { return nil }
        let frozen: AVComposition = (composition.copy() as? AVComposition) ?? composition
        return (frozen, videoComposition)
    }

    /// Rebuilds what the player plays from the edit.
    /// Audio and video are laid out in an AVComposition; the picture of every frame is
    /// then drawn by CoreStudioCompositor from the plan (CompositionInstruction) built here.
    /// Swaps in a rebuilt timeline WITHOUT losing the playhead (a new item would start at 0)
    /// and keeps playing if it was playing.
    private func install(_ item: AVPlayerItem, resumeAt time: Double) {
        let rate = player.rate
        restoringTime = true
        player.replaceCurrentItem(with: item)
        let duration = item.asset.duration.seconds
        let target = max(0, duration.isFinite ? min(time, duration) : time)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.restoringTime = false
                self.onTimeChanged?(target)
                if rate != 0 { self.player.rate = rate }
            }
        }
    }

    func updateComposition(sequence: EditSequence, mediaAssets: [MediaAsset], resumeAt resumeTime: Double = 0) {
        CrashReporter.log("rebuild composition: \(sequence.tracks.map { $0.clips.count }) clips, \(sequence.width)x\(sequence.height)")
        let newComposition = AVMutableComposition()
        let renderSize = CGSize(width: sequence.width, height: sequence.height)
        let assetMap = Dictionary(mediaAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let docsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let frame = 1.0 / max(1, sequence.frameRate)

        /// A clip as it ended up in the timeline, with its transition window
        struct Placed {
            let clip: Clip
            let layer: RenderLayer
            let previous: RenderLayer?      // outgoing clip of a cut transition
            let window: (Double, Double)?   // transition window
        }
        var placedVideo: [UUID: [Placed]] = [:]
        var cutTimes = Set<Double>([0])
        var timelineEnd = 0.0

        // IMPORTANT: an AVAssetTrack does not keep its AVAsset alive. If the asset is freed,
        // inserting the track fails ("The operation could not be completed"). So every asset
        // opened during the rebuild is kept here until the rebuild is done.
        var openAssets: [UUID: AVURLAsset] = [:]
        var keepAlive: [AVAsset] = []

        func sourceTrack(for clip: Clip, _ type: AVMediaType) -> AVAssetTrack? {
            guard let info = assetMap[clip.mediaAssetID] else { return nil }
            if let asset = openAssets[info.id] { return asset.tracks(withMediaType: type).first }
            let url = docsDirectory.appendingPathComponent(info.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                CrashReporter.log("missing media file: \(info.relativePath)")
                return nil
            }
            let asset = AVURLAsset(url: url)
            openAssets[info.id] = asset
            return asset.tracks(withMediaType: type).first
        }

        /// Inserts `clip` (optionally extended by `lead` seconds before and `tail` after, for transitions).
        @discardableResult
        func insert(_ clip: Clip, source: AVAssetTrack, into track: AVMutableCompositionTrack, lead: Double, tail: Double) -> Bool {
            let rate = clip.playbackRate
            let sourceLength = source.timeRange.end.seconds
            let srcIn = max(0, clip.sourceInPoint - lead * rate)
            let srcOut = min(sourceLength, clip.sourceOutPoint + tail * rate)
            let srcDur = srcOut - srcIn
            guard srcDur > 0.01 else { return false }
            let at = CMTime(seconds: clip.startTime - lead, preferredTimescale: 600)
            let range = CMTimeRange(start: CMTime(seconds: srcIn, preferredTimescale: 600),
                                    duration: CMTime(seconds: srcDur, preferredTimescale: 600))
            do {
                try track.insertTimeRange(range, of: source, at: at)
                if abs(rate - 1) > 0.0001 {
                    track.scaleTimeRange(CMTimeRange(start: at, duration: range.duration),
                                         toDuration: CMTime(seconds: srcDur / rate, preferredTimescale: 600))
                }
                return true
            } catch {
                CrashReporter.log("insert failed for \(clip.name): \(error.localizedDescription)")
                return false
            }
        }

        for track in sequence.tracks where !track.isMuted {
            // Keep clips in time order and drop overlapping ones
            var clips: [Clip] = []
            for clip in track.clips.sorted(by: { $0.startTime < $1.startTime }) where clip.sourceDuration > 0.01 {
                if let last = clips.last, clip.startTime < last.endTime - 0.001 {
                    CrashReporter.log("skipped overlapping clip \(clip.name)")
                    continue
                }
                clips.append(clip)
            }
            timelineEnd = max(timelineEnd, clips.last?.endTime ?? 0)

            if track.type == .audio {
                guard let comp = newComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                for clip in clips {
                    if let source = sourceTrack(for: clip, .audio) { insert(clip, source: source, into: comp, lead: 0, tail: 0) }
                }
                continue
            }

            // Video: clips alternate between two composition tracks (A/B), so two
            // neighbours can overlap during a transition.
            guard let compA = newComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compB = newComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let sources = clips.map { $0.isTitle ? nil : sourceTrack(for: $0, .video) }

            // Media available beyond each clip's edges (timeline seconds); titles have no limit
            func handleBefore(_ i: Int) -> Double {
                clips[i].isTitle ? .greatestFiniteMagnitude : clips[i].sourceInPoint / clips[i].playbackRate
            }
            func handleAfter(_ i: Int) -> Double {
                guard !clips[i].isTitle else { return .greatestFiniteMagnitude }
                let length = sources[i]?.timeRange.end.seconds ?? clips[i].sourceOutPoint
                return max(0, length - clips[i].sourceOutPoint) / clips[i].playbackRate
            }

            var lead = Array(repeating: 0.0, count: clips.count)
            var tail = Array(repeating: 0.0, count: clips.count)
            var windows: [(Double, Double)?] = Array(repeating: nil, count: clips.count)
            var hasOutgoing = Array(repeating: false, count: clips.count)

            for i in clips.indices {
                guard let transition = clips[i].transitionIn else { continue }
                let duration = max(frame, min(transition.duration, clips[i].duration))
                if i > 0, abs(clips[i - 1].endTime - clips[i].startTime) < frame * 0.75 {
                    // Across the cut: half before, half after, limited by available media
                    let half = duration / 2
                    // (each side at most half of the neighbouring clip, so windows never overlap)
                    let l = min(half, handleBefore(i), clips[i - 1].duration / 2)
                    let t = min(half, handleAfter(i - 1), clips[i].duration / 2)
                    if l + t >= frame {
                        lead[i] = l
                        tail[i - 1] = t
                        windows[i] = (clips[i].startTime - l, clips[i].startTime + t)
                        hasOutgoing[i] = true
                    }
                } else {
                    // Nothing right before it: transition in from beneath
                    windows[i] = (clips[i].startTime, clips[i].startTime + duration)
                }
            }

            var layers: [RenderLayer?] = Array(repeating: nil, count: clips.count)
            for i in clips.indices {
                let clip = clips[i]
                if clip.isTitle {
                    layers[i] = RenderLayer(trackID: nil, clip: clip, preferredTransform: .identity, naturalSize: renderSize)
                    continue
                }
                guard let source = sources[i] else { continue }
                let comp = i % 2 == 0 ? compA : compB
                guard insert(clip, source: source, into: comp, lead: lead[i], tail: tail[i]) else { continue }
                layers[i] = RenderLayer(trackID: comp.trackID, clip: clip,
                                        preferredTransform: source.preferredTransform, naturalSize: source.naturalSize)
            }

            for i in clips.indices {
                guard let layer = layers[i] else { continue }
                let previous = hasOutgoing[i] ? layers[i - 1] : nil
                placedVideo[track.id, default: []].append(Placed(clip: clips[i], layer: layer, previous: previous, window: windows[i]))
                cutTimes.insert(clips[i].startTime)
                cutTimes.insert(clips[i].endTime)
                if let w = windows[i] { cutTimes.insert(w.0); cutTimes.insert(w.1) }
            }
        }

        // A black picture under everything, for the whole timeline: titles and gaps
        // still have frames, and the timeline is as long as its last clip or title.
        let blackAsset = BlackVideo.url().map { AVURLAsset(url: $0) }
        if let blackAsset { keepAlive.append(blackAsset) }
        if !placedVideo.isEmpty, timelineEnd > 0.01,
           let black = blackAsset?.tracks(withMediaType: .video).first,
           let base = newComposition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let one = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
            do {
                try base.insertTimeRange(one, of: black, at: .zero)
                base.scaleTimeRange(CMTimeRange(start: .zero, duration: one.duration),
                                    toDuration: CMTime(seconds: timelineEnd, preferredTimescale: 600))
            } catch {
                CrashReporter.log("black base failed: \(error.localizedDescription)")
            }
        }

        // Empty tracks play fine but make export fail ("Operation Stopped")
        for t in newComposition.tracks where t.segments.isEmpty {
            newComposition.removeTrack(t)
        }

        self.composition = newComposition
        let item = AVPlayerItem(asset: newComposition)
        item.audioTimePitchAlgorithm = .spectral // natural voices when speed changes

        let total = newComposition.duration.seconds
        guard !placedVideo.isEmpty, total > 0.01 else {
            self.videoComposition = nil
            install(item, resumeAt: resumeTime)
            CrashReporter.log("rebuild done (audio only), \(total)s, \(openAssets.count + keepAlive.count) files")
            return
        }

        // The plan: contiguous time ranges covering the whole timeline.
        var cuts: [Double] = []
        for t in cutTimes.sorted() where t >= 0 && t < total - 0.0005 {
            if let last = cuts.last, t - last < 0.001 { continue }
            cuts.append(t)
        }
        if cuts.first != 0 { cuts.insert(0, at: 0) }
        cuts.append(total)

        let videoTrackOrder = sequence.tracks.filter { $0.type == .video && !$0.isMuted }.map(\.id)
        var instructions: [CompositionInstruction] = []
        for i in 0..<(cuts.count - 1) {
            let start = cuts[i], end = cuts[i + 1]
            let mid = (start + end) / 2
            var tracks: [TrackRender] = []
            for trackID in videoTrackOrder {
                guard let placed = placedVideo[trackID] else { continue }
                // A clip whose transition window covers this moment wins (it's coming in)
                if let p = placed.first(where: { p in
                    guard let w = p.window, p.previous != nil else { return false }
                    return mid >= w.0 && mid < w.1
                }) {
                    tracks.append(TrackRender(incoming: p.layer, outgoing: p.previous, transition: p.clip.transitionIn, window: p.window))
                } else if let p = placed.first(where: { mid >= $0.clip.startTime && mid < $0.clip.endTime }) {
                    tracks.append(TrackRender(incoming: p.layer, outgoing: nil, transition: p.clip.transitionIn, window: p.window))
                }
            }
            let startCM = CMTime(seconds: start, preferredTimescale: 600)
            let endCM = i == cuts.count - 2 ? newComposition.duration : CMTime(seconds: end, preferredTimescale: 600)
            instructions.append(CompositionInstruction(timeRange: CMTimeRange(start: startCM, end: endCM), tracks: tracks))
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = CoreStudioCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(seconds: frame, preferredTimescale: 60000)
        videoComposition.instructions = instructions

        self.videoComposition = videoComposition
        item.videoComposition = videoComposition
        install(item, resumeAt: resumeTime)
        CrashReporter.log("rebuild done: \(instructions.count) segments, \(total)s, \(openAssets.count + keepAlive.count) files")
    }
}
