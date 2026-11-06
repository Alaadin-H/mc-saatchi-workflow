import Foundation
import AVFoundation

/// This file was missing from the project (Tab 22 in the doc is empty),
/// but EditorState and MediaBinView both use MediaImportService.
final class MediaImportService {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Copies the file into Documents/Media and returns a MediaAsset whose
    /// relativePath is relative to Documents (that's what PlaybackEngine expects).
    func copyMediaToLocalStorage(sourceURL: URL) -> MediaAsset? {
        // Files from the Files app (DocumentPicker with asCopy: false) are security-scoped.
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let mediaDir = documentsDirectory.appendingPathComponent("Media", isDirectory: true)
        try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        let id = UUID()
        let ext = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let fileName = "\(id.uuidString).\(ext)"
        let destURL = mediaDir.appendingPathComponent(fileName)

        do {
            try fileManager.copyItem(at: sourceURL, to: destURL)
        } catch {
            print("Media copy failed: \(error)")
            return nil
        }

        let avAsset = AVURLAsset(url: destURL)
        let duration = avAsset.duration.seconds
        guard duration.isFinite, duration > 0 else {
            try? fileManager.removeItem(at: destURL)
            print("Unreadable media: \(sourceURL.lastPathComponent)")
            return nil
        }

        let videoTrack = avAsset.tracks(withMediaType: .video).first
        var width = 1920.0, height = 1080.0
        if let vt = videoTrack {
            let size = vt.naturalSize.applying(vt.preferredTransform)
            width = Double(abs(size.width))
            height = Double(abs(size.height))
        }

        return MediaAsset(
            id: id,
            name: sourceURL.lastPathComponent,
            type: videoTrack != nil ? .video : .audio,
            relativePath: "Media/\(fileName)",
            durationSeconds: duration,
            naturalSizeWidth: width,
            naturalSizeHeight: height
        )
    }
}
