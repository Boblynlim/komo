import SwiftUI
import UniformTypeIdentifiers

struct TabTransfer: Codable, Transferable {
    let tabID: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}

struct SidebarView: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var showDownloads = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab list
            List(selection: $tabManager.selectedTabID) {
                // New Tab button at top
                Button(action: { tabManager.createNewTab() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("New Tab")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)

                // Folders
                ForEach(tabManager.folders) { folder in
                    FolderSection(folder: folder)
                }

                // Unfoldered tabs
                HStack(spacing: 5) {
                    Text("Tabs")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(tabManager.tabs.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 16)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                    Spacer()
                }
                .listRowSeparator(.hidden)

                ForEach(tabManager.unfolderedTabs) { tab in
                    SidebarTabRow(tab: tab)
                        .tag(tab.id)
                        .draggable(TabTransfer(tabID: tab.id.uuidString))
                        .contextMenu {
                            tabContextMenu(for: tab)
                        }
                }
            }
            .listStyle(.sidebar)

            // Bottom bar — flat, no background distinction
            HStack(spacing: 0) {
                // Downloads icon — bottom left
                Button(action: { showDownloads.toggle() }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .popover(isPresented: $showDownloads, arrowEdge: .top) {
                    DownloadsPopover()
                        .environmentObject(downloadManager)
                }

                Spacer()

                // Pulse icon
                Button(action: {
                    NotificationCenter.default.post(name: .togglePulse, object: nil)
                }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.kPink)
                .help("Scout — Discover new stuff (⌘⇧P)")

                // New folder icon — bottom right
                Button(action: { isCreatingFolder = true }) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $isCreatingFolder) {
            NewFolderSheet(isPresented: $isCreatingFolder) { name in
                tabManager.createFolder(name: name)
            }
        }
    }

    @ViewBuilder
    func tabContextMenu(for tab: Tab) -> some View {
        Button(tab.isFavorite ? "Unfavorite" : "Favorite") {
            tabManager.toggleFavorite(tab)
        }
        if !tabManager.folders.isEmpty {
            Menu("Move to Folder") {
                ForEach(tabManager.folders) { folder in
                    Button(folder.name) {
                        tabManager.moveTab(tab, toFolder: folder)
                    }
                }
                Divider()
                Button("Remove from Folder") {
                    tabManager.removeTabFromFolder(tab)
                }
            }
        }
        Button("Close Tab") {
            tabManager.closeTab(tab)
        }
    }
}

// MARK: - Downloads Popover

struct DownloadsPopover: View {
    @EnvironmentObject var downloadManager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Downloads")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if downloadManager.downloads.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.quaternary)
                    Text("No downloads yet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloadManager.recentDownloads.prefix(10)) { item in
                            DownloadRow(item: item)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 260)
    }
}

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // File icon
            Image(systemName: fileIcon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.isComplete {
                    Text(item.timeAgo)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if let error = item.error {
                    Text("Failed")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                } else {
                    ProgressView(value: item.progress)
                        .scaleEffect(y: 0.5)
                }
            }

            Spacer()

            if isHovering && item.isComplete {
                Button(action: { downloadManager.revealInFinder(item) }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { isHovering = $0 }
        .onTapGesture {
            if item.isComplete {
                downloadManager.revealInFinder(item)
            }
        }
    }

    var fileIcon: String {
        let ext = (item.fileName as NSString).pathExtension.lowercased()
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

// MARK: - Folder Section

struct FolderSection: View {
    @ObservedObject var folder: TabFolder
    @EnvironmentObject var tabManager: TabManager
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var isTargeted = false

    var folderTabs: [Tab] {
        folder.tabIDs.compactMap { id in tabManager.tab(for: id) }
    }

    var body: some View {
        Section(isExpanded: $folder.isExpanded) {
            ForEach(folderTabs) { tab in
                SidebarTabRow(tab: tab)
                    .tag(tab.id)
                    .draggable(TabTransfer(tabID: tab.id.uuidString))
                    .contextMenu {
                        Menu("Move to Folder") {
                            ForEach(tabManager.folders.filter { $0.id != folder.id }) { otherFolder in
                                Button(otherFolder.name) {
                                    tabManager.moveTab(tab, toFolder: otherFolder)
                                }
                            }
                            Divider()
                            Button("Remove from Folder") {
                                tabManager.removeTabFromFolder(tab)
                            }
                        }
                        Button("Close Tab") {
                            tabManager.closeTab(tab)
                        }
                    }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                if isRenaming {
                    TextField("Folder name", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .onSubmit {
                            tabManager.renameFolder(folder, to: renameText)
                            isRenaming = false
                        }
                } else {
                    Text(folder.name)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(folderTabs.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 16)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.vertical, 2)
            .background(isTargeted ? Color.kPink.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            .dropDestination(for: TabTransfer.self) { items, _ in
                for item in items {
                    if let uuid = UUID(uuidString: item.tabID),
                       let tab = tabManager.tab(for: uuid) {
                        tabManager.moveTab(tab, toFolder: folder)
                    }
                }
                return true
            } isTargeted: { targeted in
                isTargeted = targeted
            }
            .contextMenu {
                Button("Rename") {
                    renameText = folder.name
                    isRenaming = true
                }
                Divider()
                Button("Delete Folder", role: .destructive) {
                    tabManager.deleteFolder(folder)
                }
            }
        }
    }
}

// MARK: - Tab Row

struct SidebarTabRow: View {
    @ObservedObject var tab: Tab
    @EnvironmentObject var tabManager: TabManager
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Favicon or star
            if tab.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .frame(width: 16, height: 16)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if tab.isLoading {
                            ProgressView()
                                .scaleEffect(0.4)
                        } else {
                            Image(systemName: "globe")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
            }

            Text(tab.title)
                .font(.system(size: 13, weight: .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if isHovering {
                Button(action: { tabManager.closeTab(tab) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 3)
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 4))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            tabManager.selectedTabID = tab.id
            NotificationCenter.default.post(name: .dismissOverlays, object: nil)
        }
    }
}

// MARK: - New Folder Sheet

struct NewFolderSheet: View {
    @Binding var isPresented: Bool
    @State private var name = ""
    let onCreate: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("New Folder")
                .font(.system(size: 14, weight: .semibold))

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { create() }

            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onCreate(trimmed)
        isPresented = false
    }
}
