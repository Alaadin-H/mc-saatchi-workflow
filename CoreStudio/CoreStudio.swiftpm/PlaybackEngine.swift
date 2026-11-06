import Foundation
import AVFoundation
import Combine

final class PlaybackEngine: ObservableObject {
    @Published var player: AVPlayer = AVPlayer()
    @Published var isPlaying: Bool = false

    var onTimeChanged: ((Double) -> Void)?
    var onStatusChanged: ((Bool) -> Void)?
    
    private var composition: AVMutableComposition?
    private var videoComposition: AVMutableVideoComposition?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var currentRate: Float = 0.0

    init() {
        setupObservers()
    }

    deinit {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
    }

    private func setupObservers() {
        let interval = CMTime(value: 1, timescale: 30)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.onTimeChanged?(time.seconds)
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

    func updateComposition(sequence: EditSequence, mediaAssets: [MediaAsset]) {
        let newComposition = AVMutableComposition()
        let renderSize = CGSize(width: sequence.width, height: sequence.height)
        
        CrashReporter.log("rebuild composition: \(sequence.tracks.map { $0.clips.count }) clips, \(sequence.width)x\(sequence.height)")
        // FIX: never crash on duplicate asset IDs
        let assetMap = Dictionary(mediaAssets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let docsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        var compositionTracks: [UUID: AVMutableCompositionTrack] = [:]
        var times = Set<Double>()
        times.insert(0) // Ensure instruction spans from 0
        
        var hasVideoClips = false
        
        // 1. Map assets into Composition Tracks
        for track in sequence.tracks {
            guard !track.isMuted else { continue }
            let trackType: AVMediaType = (track.type == .video) ? .video : .audio
            guard let compTrack = newComposition.addMutableTrack(withMediaType: trackType, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            compositionTracks[track.id] = compTrack

            // FIX: insert clips in time order, otherwise insertTimeRange shifts clips that were inserted earlier
            var trackEnd: Double = 0
            for clip in track.clips.sorted(by: { $0.startTime < $1.startTime }) {
                guard let assetInfo = assetMap[clip.mediaAssetID] else { continue }
                let fileURL = docsDirectory.appendingPathComponent(assetInfo.relativePath)
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    CrashReporter.log("missing media file: \(assetInfo.relativePath)")
                    continue
                }
                let avAsset = AVURLAsset(url: fileURL)
                guard let sourceTrack = avAsset.tracks(withMediaType: trackType).first else { continue }

                // FIX: skip clips that overlap the previous clip on the same track (insertTimeRange would push them around)
                guard clip.startTime >= trackEnd - 0.001, clip.duration > 0.01 else {
                    CrashReporter.log("skipped overlapping clip \(clip.name)")
                    continue
                }
                // FIX: clamp the source range to the real media length
                let sourceLength = sourceTrack.timeRange.end.seconds
                let srcIn = max(0, min(clip.sourceInPoint, sourceLength))
                let srcDur = max(0, min(clip.duration, sourceLength - srcIn))
                guard srcDur > 0.01 else { continue }
                trackEnd = clip.startTime + srcDur

                let sourceRange = CMTimeRange(start: CMTime(seconds: srcIn, preferredTimescale: 600),
                                              duration: CMTime(seconds: srcDur, preferredTimescale: 600))
                let startTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)

                do {
                    try compTrack.insertTimeRange(sourceRange, of: sourceTrack, at: startTime)
                    if trackType == .video {
                        hasVideoClips = true
                        times.insert(clip.startTime)
                        times.insert(clip.startTime + srcDur)
                    }
                } catch {
                    print("Failed to insert track slice: \(error)")
                }
            }
        }
        
        if !hasVideoClips {
            self.composition = newComposition
            self.videoComposition = nil
            let playerItem = AVPlayerItem(asset: newComposition)
            self.player.replaceCurrentItem(with: playerItem)
            return
        }
        
        let newVideoComposition = AVMutableVideoComposition()
        newVideoComposition.renderSize = renderSize
        // FIX: works for fractional rates like 29.97 too
        newVideoComposition.frameDuration = CMTime(seconds: 1.0 / sequence.frameRate, preferredTimescale: 60000)
        
        // 2. Resolve AVVideoComposition overlaps and transforms
        var instructions: [AVMutableVideoCompositionInstruction] = []
        // FIX: instructions must cover the WHOLE composition with no gaps (including audio that runs past the last video clip)
        let totalDuration = newComposition.duration.seconds
        times.insert(totalDuration)
        var sortedTimes: [Double] = []
        for t in times.sorted() where t <= totalDuration {
            if let last = sortedTimes.last, t - last < 0.01 { continue }
            sortedTimes.append(t)
        }
        if sortedTimes.count > 1 { sortedTimes[sortedTimes.count - 1] = totalDuration }
        
        // Render Order: High track index (e.g. Video 2) is visually ON TOP of lower track index (e.g. Video 1).
        // For layerInstructions, index 0 is at the top. So we reverse the video tracks array.
        // FIX: was `filter { 0.isMuted }` (doesn't compile). Only unmuted VIDEO tracks get layer instructions.
        let videoTracks = sequence.tracks.filter { $0.type == .video && !$0.isMuted }.reversed()
        
        for i in 0..<max(0, sortedTimes.count - 1) {
            let start = sortedTimes[i]
            let end = sortedTimes[i+1]
            let mid = (start + end) / 2.0
            
            let instruction = AVMutableVideoCompositionInstruction()
            // FIX: start/end (not start/duration) so neighbouring instructions touch exactly, no rounding gaps
            let endCM = (i == sortedTimes.count - 2) ? newComposition.duration : CMTime(seconds: end, preferredTimescale: 600)
            instruction.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: endCM)
            
            var layerInstructions: [AVVideoCompositionLayerInstruction] = []
            
            for track in videoTracks {
                if let clip = track.clips.first(where: { mid >= $0.startTime && mid <= $0.endTime }),
                   let compTrack = compositionTracks[track.id],
                   let assetInfo = assetMap[clip.mediaAssetID] {
                    
                    let fileURL = docsDirectory.appendingPathComponent(assetInfo.relativePath)
                    let avAsset = AVURLAsset(url: fileURL)
                    guard let sourceTrack = avAsset.tracks(withMediaType: .video).first else { continue }
                    
                    let layerInst = AVMutableVideoCompositionLayerInstruction(assetTrack: compTrack)
                    
                    // Matrix Transform Logic: Center + Aspect Fit + User Adjustments
                    let prefXform = sourceTrack.preferredTransform
                    let isPortrait = abs(prefXform.a) < 0.1 && abs(prefXform.d) < 0.1
                    let trackWidth = isPortrait ? sourceTrack.naturalSize.height : sourceTrack.naturalSize.width
                    let trackHeight = isPortrait ? sourceTrack.naturalSize.width : sourceTrack.naturalSize.height
                    
                    let fitScale = min(renderSize.width / trackWidth, renderSize.height / trackHeight)
                    
                    let userScale = CGFloat(clip.transform.scaleX)
                    let userRot = CGFloat(clip.transform.rotationDegrees) * .pi / 180.0
                    let userTx = CGFloat(clip.transform.positionX)
                    let userTy = CGFloat(clip.transform.positionY)
                    
                    let centerX = renderSize.width / 2.0 + userTx
                    let centerY = renderSize.height / 2.0 + userTy
                    
                    var finalXform = CGAffineTransform(translationX: centerX, y: centerY)
                    finalXform = finalXform.rotated(by: userRot)
                    finalXform = finalXform.scaledBy(x: fitScale * userScale, y: fitScale * userScale)
                    
                    let transformedBounds = CGRect(origin: .zero, size: sourceTrack.naturalSize).applying(prefXform)
                    finalXform = finalXform.translatedBy(x: -transformedBounds.midX, y: -transformedBounds.midY)
                    finalXform = prefXform.concatenating(finalXform)
                    
                    let cmStartTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
                    layerInst.setTransform(finalXform, at: cmStartTime)
                    layerInst.setOpacity(Float(clip.opacity), at: cmStartTime)
                    
                    layerInstructions.append(layerInst)
                }
            }
            
            instruction.layerInstructions = layerInstructions // Empty array naturally creates a black background gap
            instructions.append(instruction)
        }

        newVideoComposition.instructions = instructions
        self.composition = newComposition

        let playerItem = AVPlayerItem(asset: newComposition)
        // FIX: an invalid video composition throws an exception that kills the app instantly.
        // Validate first; if it's invalid, play without transforms/layering instead of crashing.
        let fullRange = CMTimeRange(start: .zero, duration: newComposition.duration)
        if newVideoComposition.isValid(for: newComposition, timeRange: fullRange, validationDelegate: nil) {
            self.videoComposition = newVideoComposition
            playerItem.videoComposition = newVideoComposition
        } else {
            self.videoComposition = nil
            CrashReporter.log("video composition INVALID, playing without it (\(instructions.count) instructions)")
        }
        self.player.replaceCurrentItem(with: playerItem)
        CrashReporter.log("rebuild composition done, duration \(newComposition.duration.seconds)s")
    }
}

