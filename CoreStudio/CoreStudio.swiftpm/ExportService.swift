import Foundation
import AVFoundation
import SwiftUI
import UIKit

/// Renders the timeline to a movie file, through the same compositor as playback,
/// so the export looks exactly like the preview.
final class ExportService: ObservableObject {
    enum State: Equatable {
        case idle
        case exporting(progress: Double)
        case finished(URL)
        case failed(String)
    }

    enum Quality: String, CaseIterable, Identifiable {
        case high = "High"
        case medium = "Medium"
        var id: String { rawValue }
        var preset: String { self == .high ? AVAssetExportPresetHighestQuality : AVAssetExportPresetMediumQuality }
    }

    @Published var state: State = .idle
    private var session: AVAssetExportSession?
    private var timer: Timer?

    func start(composition: AVComposition, videoComposition: AVVideoComposition?, name: String, quality: Quality) {
        cancel()
        guard composition.duration.seconds > 0.05 else {
            state = .failed("The timeline is empty.")
            return
        }
        guard let session = AVAssetExportSession(asset: composition, presetName: quality.preset) else {
            state = .failed("This device can't export with these settings.")
            return
        }
        let safeName = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName.isEmpty ? "CoreStudio" : safeName)-\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: url)

        session.outputURL = url
        session.outputFileType = .mov
        session.videoComposition = videoComposition
        session.audioTimePitchAlgorithm = .spectral
        self.session = session
        state = .exporting(progress: 0)
        CrashReporter.log("export started (\(quality.rawValue))")

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = self.session, case .exporting = self.state else { return }
                self.state = .exporting(progress: Double(s.progress))
            }
        }

        session.exportAsynchronously { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.timer?.invalidate()
                self.timer = nil
                switch session.status {
                case .completed:
                    self.state = .finished(url)
                    CrashReporter.log("export finished")
                case .cancelled:
                    self.state = .idle
                default:
                    // Include the codes so the real cause is visible (e.g. AVFoundation -11838)
                    var message = "Export failed."
                    if let error = session.error as NSError? {
                        message = "\(error.localizedDescription) (\(error.domain) \(error.code))"
                        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                            message += " — \(underlying.localizedDescription) (\(underlying.domain) \(underlying.code))"
                        }
                        if let reason = error.localizedFailureReason { message += " — \(reason)" }
                    }
                    self.state = .failed(message)
                    CrashReporter.log("export failed: \(message)")
                }
                self.session = nil
            }
        }
    }

    func cancel() {
        session?.cancelExport()
        session = nil
        timer?.invalidate()
        timer = nil
        state = .idle
    }
}

/// "Save to Files" sheet for the exported movie.
struct ExportSaver: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: true)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
