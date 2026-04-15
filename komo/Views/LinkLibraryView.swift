import SwiftUI

struct LinkLibraryView: View {
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var isAddingTag = false
    @State private var newTagName = ""

    var body: some View {
        HSplitView {
            // Left sidebar — navigation
            linkSidebar
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            // Right — link list
            linkList
        }
    }

    // MARK: - Sidebar

    var linkSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $linkStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onChange(of: linkStore.searchQuery) {
                        if !linkStore.searchQuery.isEmpty {
                            linkStore.filter = .search
                        } else if case .search = linkStore.filter {
                            linkStore.filter = .inbox
                        }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Nav items
            VStack(spacing: 2) {
                NavItem(icon: "tray", label: "Inbox", isSelected: linkStore.filter == .inbox) {
                    linkStore.filter = .inbox
                    linkStore.searchQuery = ""
                }
                NavItem(icon: "archivebox", label: "Archive", isSelected: linkStore.filter == .archive) {
                    linkStore.filter = .archive
                    linkStore.searchQuery = ""
                }
            }
            .padding(.horizontal, 8)

            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

            // Tags
            HStack {
                Text("Tags")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { isAddingTag = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 2) {
                    if isAddingTag {
                        HStack(spacing: 6) {
                            Text("#")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.purple)
                            TextField("tag name", text: $newTagName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .onSubmit {
                                    let tag = newTagName.trimmingCharacters(in: .whitespaces).lowercased()
                                    if !tag.isEmpty {
                                        // Tag will appear once a link uses it
                                    }
                                    newTagName = ""
                                    isAddingTag = false
                                }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                    }

                    ForEach(linkStore.allTags, id: \.self) { tag in
                        TagNavItem(tag: tag, isSelected: linkStore.filter == .tag(tag)) {
                            linkStore.filter = .tag(tag)
                            linkStore.searchQuery = ""
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(.bar)
    }

    // MARK: - Link list

    var linkList: some View {
        VStack(spacing: 0) {
            if linkStore.filteredLinks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(linkStore.groupedLinks, id: \.0) { dateLabel, links in
                            Section {
                                ForEach(links) { link in
                                    LinkRow(link: link)
                                }
                            } header: {
                                Text(dateLabel)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.bar)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No saved links")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Press \u{2318}D to save the current page")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Components

struct NavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

struct TagNavItem: View {
    let tag: String
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var linkStore: LinkStore
    @State private var isRenaming = false
    @State private var renameText = ""

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("#")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 16)

                if isRenaming {
                    TextField("", text: $renameText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit {
                            linkStore.renameTag(tag, to: renameText)
                            isRenaming = false
                        }
                } else {
                    Text(tag)
                        .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameText = tag
                isRenaming = true
            }
            Button("Delete Tag", role: .destructive) {
                linkStore.deleteTag(tag)
            }
        }
    }
}

struct LinkRow: View {
    let link: SavedLink
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Favicon placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary)
                .frame(width: 20, height: 20)
                .overlay {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

            // Title
            Text(link.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            // Tags
            HStack(spacing: 4) {
                ForEach(link.tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.purple.opacity(0.7))
                }
            }

            // Actions on hover
            if isHovering {
                Menu {
                    Button("Open") { openLink() }
                    Button("Open in New Tab") { openInNewTab() }
                    Divider()
                    if link.isArchived {
                        Button("Move to Inbox") { linkStore.unarchive(link) }
                    } else {
                        Button("Archive") { linkStore.archive(link) }
                    }
                    Divider()
                    Button("Delete", role: .destructive) { linkStore.delete(link) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { openLink() }
        .onHover { isHovering = $0 }
    }

    private func openLink() {
        if let url = URL(string: link.url), let tab = tabManager.selectedTab {
            tab.load(url)
        }
    }

    private func openInNewTab() {
        if let url = URL(string: link.url) {
            tabManager.createNewTab(url: url)
        }
    }
}
