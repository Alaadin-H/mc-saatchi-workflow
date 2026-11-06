import Foundation
import AVFoundation

struct TimelineEngine {
    static func calculateSequenceDuration(sequence: EditSequence) -> Double {
        var maxTime: Double = 0.0
        for track in sequence.tracks {
            for clip in track.clips {
                if clip.endTime > maxTime {
                    maxTime = clip.endTime
                }
            }
        }
        return max(maxTime, 5.0) 
    }
    
    static func pointsToSeconds(offset: CGFloat, pointsPerSecond: CGFloat) -> Double {
        Double(offset / max(pointsPerSecond, 1.0))
    }
    
    static func secondsToPoints(seconds: Double, pointsPerSecond: CGFloat) -> CGFloat {
        CGFloat(seconds) * pointsPerSecond
    }
}

