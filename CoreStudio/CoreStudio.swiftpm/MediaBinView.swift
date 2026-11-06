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
        VStack(spacing: 0) {
            PanelHeader(title: "Media", icon: "square.stack") {
                PhotosPicker(selection: $selectedPhotoItem, matching: .videos) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Palette.textPrimary)
                        .frame(width: 28, height: 28)
                }
                IconButton(systemName: "folder.badge.plus", size: 28) { showDocumentPicker = true }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                CrashReporter.log("photos import started")
                Task {
                    do {
                        if let data = try await newItem.loadTransferable(type: VideoTransferable.self) {
                            await MainActor.run { importMedia(from: data.url) }
                        } else {
                            CrashReporter.log("photos import: no data")
                        }
                    } catch {
                        CrashReporter.log("photos import failed: \(error.localizedDescription)")
                    }
                }
            }

            if editorState.project.mediaAssets.isEmpty {
                EmptyState(icon: "film", title: "No media yet", message: "Import videos from Photos or Files")
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.xs) {
                        ForEach(editorState.project.mediaAssets) { asset in
                            MediaRow(asset: asset) { addAssetToTimeline(asset) }
                        }
                    }
                    .padding(DS.Space.s)
                }
            }
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


struct MediaRow: View {
    let asset: MediaAsset
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s) {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(asset.type == .video ? DS.Palette.videoClip.opacity(0.25) : DS.Palette.audioClip.opacity(0.25))
                .frame(width: 44, height: 30)
                .overlay(
                    Image(systemName: asset.type == .video ? "video.fill" : "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(asset.type == .video ? DS.Palette.videoClipSelected : DS.Palette.audioClipSelected)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.name).font(DS.Typo.label).foregroundColor(DS.Palette.textPrimary).lineLimit(1)
                Text(String(format: "%.1fs", asset.durationSeconds)).font(DS.Typo.caption).foregroundColor(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
            IconButton(systemName: "plus", tint: DS.Palette.accent, size: 26, action: onAdd)
        }
        .padding(DS.Space.s)
        .background(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).fill(DS.Palette.raised))
    }
}
