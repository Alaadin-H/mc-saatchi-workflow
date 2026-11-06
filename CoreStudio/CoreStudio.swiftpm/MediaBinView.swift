import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct VideoTransferable: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let copyURL = tempDir.appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: copyURL.path) {
                try FileManager.default.removeItem(at: copyURL)
            }
            try FileManager.default.copyItem(at: received.file, to: copyURL)
            return Self(url: copyURL)
        }
    }
}

struct MediaBinView: View {
    @EnvironmentObject var editorState: EditorState
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDocumentPicker = false

    var body: some View {
        VStack {
            HStack {
                Text("Media Bin").font(.subheadline).bold()
                Spacer()

                PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                    Image(systemName: "photo.on.rectangle")
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    CrashReporter.log("photos import started")
                    Task {
                        do {
                            if let data = try await newItem.loadTransferable(type: VideoTransferable.self) {
                                // FIX: UI/project changes must happen on the main thread
                                await MainActor.run { importMedia(from: data.url) }
                            } else {
                                CrashReporter.log("photos import: no data")
                            }
                        } catch {
                            CrashReporter.log("photos import failed: \(error.localizedDescription)")
                        }
                    }
                }

                Button(action: { showDocumentPicker = true }) { Image(systemName: "folder.badge.plus") }
            }
            .padding([.top, .horizontal])

            List(editorState.project.mediaAssets) { asset in
                HStack {
                    Image(systemName: asset.type == .video ? "video.fill" : "music.note")
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading) {
                        Text(asset.name).font(.caption).lineLimit(1)
                        Text(String(format: "%.1fs", asset.durationSeconds))
                            .font(.caption2).foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: { addAssetToTimeline(asset) }) { Image(systemName: "plus.circle") }
                }
            }
            .listStyle(.plain)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { url in importMedia(from: url) }
        }
    }

    private func importMedia(from url: URL) {
        CrashReporter.log("import media: \(url.lastPathComponent)")
        if let asset = editorState.mediaImporter.copyMediaToLocalStorage(sourceURL: url) {
            let cmd = ImportMediaCommand(asset: asset)
            editorState.execute(cmd)
        }
    }

    private func addAssetToTimeline(_ asset: MediaAsset) {
        guard let activeSeq = editorState.project.sequences.first(where: { $0.id == editorState.project.activeSequenceID }),
              let track = activeSeq.tracks.first(where: { $0.type == (asset.type == .video ? .video : .audio) }) else { return }
        
        CrashReporter.log("add to timeline: \(asset.name) (\(asset.durationSeconds)s)")
        let cmd = AddClipToTimelineCommand(mediaAssetID: asset.id, trackID: track.id, startTime: editorState.currentTime)
        editorState.execute(cmd)
    }
}

