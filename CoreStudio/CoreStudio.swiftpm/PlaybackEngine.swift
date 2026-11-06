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

        struct Placed { let clip: Clip; let compTrackID: CMPersistentTrackID; let preferredTransform: CGAffineTransform; let naturalSize: CGSize }
        // Video clips actually placed, per editor track (bottom track first)
        var placedVideo: [UUID: [Placed]] = [:]
        var cutTimes = Set<Double>([0])

        for track in sequence.tracks where !track.isMuted {
            let mediaType: AVMediaType = track.type == .video ? .video : .audio
            guard let compTrack = newComposition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }

            // Clips are inserted in time order; overlapping clips on one track are skipped
            var trackEnd = 0.0
            for clip in track.clips.sorted(by: { $0.startTime < $1.startTime }) {
                guard let info = assetMap[clip.mediaAssetID] else { continue }
                let url = docsDirectory.appendingPathComponent(info.relativePath)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    CrashReporter.log("missing media file: \(info.relativePath)")
                    continue
                }
                let asset = AVURLAsset(url: url)
                // A video clip on a video track brings its picture; on an audio track, its sound
                guard let source = asset.tracks(withMediaType: mediaType).first else { continue }
                guard clip.startTime >= trackEnd - 0.001, clip.sourceDuration > 0.01 else {
                    CrashReporter.log("skipped overlapping clip \(clip.name)")
                    continue
                }

                let sourceLength = source.timeRange.end.seconds
                let srcIn = max(0, min(clip.sourceInPoint, sourceLength))
                let srcDur = max(0, min(clip.sourceDuration, sourceLength - srcIn))
                guard srcDur > 0.01 else { continue }
                let timelineDur = srcDur / clip.playbackRate
                let at = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                let sourceRange = CMTimeRange(start: CMTime(seconds: srcIn, preferredTimescale: 600),
                                              duration: CMTime(seconds: srcDur, preferredTimescale: 600))
                do {
                    try compTrack.insertTimeRange(sourceRange, of: source, at: at)
                    if abs(clip.playbackRate - 1) > 0.0001 {
                        compTrack.scaleTimeRange(CMTimeRange(start: at, duration: sourceRange.duration),
                                                 toDuration: CMTime(seconds: timelineDur, preferredTimescale: 600))
                    }
                } catch {
                    CrashReporter.log("insert failed for \(clip.name): \(error.localizedDescription)")
                    continue
                }
                trackEnd = clip.startTime + timelineDur

                if mediaType == .video {
                    var placedClip = clip
                    // What was really inserted (media may be shorter than the clip claims)
                    placedClip.sourceInPoint = srcIn
                    placedClip.sourceOutPoint = srcIn + srcDur
                    placedVideo[track.id, default: []].append(Placed(clip: placedClip, compTrackID: compTrack.trackID,
                                                                     preferredTransform: source.preferredTransform,
                                                                     naturalSize: source.naturalSize))
                    cutTimes.insert(clip.startTime)
                    cutTimes.insert(clip.startTime + timelineDur)
                }
            }
        }

        // Empty tracks (e.g. "Video 2" with no clips) play fine but make export fail
        // with "Operation Stopped", so they are removed.
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
            CrashReporter.log("rebuild done (audio only), \(total)s")
            return
        }

        // The plan: contiguous time ranges covering the whole timeline, each listing the
        // clips on screen in it, bottom track first.
        var cuts: [Double] = []
        for t in cutTimes.sorted() where t < total - 0.0005 {
            if let last = cuts.last, t - last < 0.001 { continue }
            cuts.append(t)
        }
        cuts.append(total)

        let videoTrackOrder = sequence.tracks.filter { $0.type == .video && !$0.isMuted }.map(\.id)
        var instructions: [CompositionInstruction] = []
        for i in 0..<(cuts.count - 1) {
            let start = cuts[i], end = cuts[i + 1]
            let mid = (start + end) / 2
            var layers: [RenderLayer] = []
            for trackID in videoTrackOrder {
                if let p = placedVideo[trackID]?.first(where: { mid >= $0.clip.startTime && mid < $0.clip.endTime }) {
                    layers.append(RenderLayer(trackID: p.compTrackID, clip: p.clip,
                                              preferredTransform: p.preferredTransform, naturalSize: p.naturalSize))
                }
            }
            let startCM = CMTime(seconds: start, preferredTimescale: 600)
            let endCM = i == cuts.count - 2 ? newComposition.duration : CMTime(seconds: end, preferredTimescale: 600)
            instructions.append(CompositionInstruction(timeRange: CMTimeRange(start: startCM, end: endCM), layers: layers))
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = CoreStudioCompositor.self
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(seconds: 1.0 / max(1, sequence.frameRate), preferredTimescale: 60000)
        videoComposition.instructions = instructions

        self.videoComposition = videoComposition
        item.videoComposition = videoComposition
        install(item, resumeAt: resumeTime)
        CrashReporter.log("rebuild done: \(instructions.count) segments, \(total)s")
    }
}
