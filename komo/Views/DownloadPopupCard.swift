import SwiftUI

struct DownloadPopupCard: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        if downloadManager.showLatestPopup, let item = downloadManager.latestDownload {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    // File icon
                    Image(systemName: iconFor(item.fileName))
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                        .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if item.isComplete {
                            Text("Download complete")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                        } else if item.error != nil {
                            Text("Download failed")
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                        } else {
                            HStack(spacing: 6) {
                                ProgressView(value: item.progress)
                                    .frame(width: 100)
                                Text("\(Int(item.progress * 100))%")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(action: { downloadManager.showLatestPopup = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .frame(width: 260)
            .onTapGesture {
                if item.isComplete {
                    downloadManager.revealInFinder(item)
                    downloadManager.showLatestPopup = false
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: downloadManager.showLatestPopup)
        }
    }

    func iconFor(_ filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "rar": return "doc.zipper"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "flac": return "music.note"
        default: return "doc"
        }
    }
}
