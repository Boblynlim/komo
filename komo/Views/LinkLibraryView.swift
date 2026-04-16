import SwiftUI

struct LinkLibraryView: View {
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var isAddingTag = false
    @State private var newTagName = ""
    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showBatchTag = false
    @State private var batchTagInput = ""

    var body: some View {
        HSplitView {
            // Left sidebar — navigation
            linkSidebar
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            // Right — link list
            VStack(spacing: 0) {
                if isSelecting {
                    selectionToolbar
                }
                linkList
            }
        }
    }

    // MARK: - Selection toolbar

    var selectionToolbar: some View {
        HStack(spacing: 12) {
            Button(action: {
                if selectedIDs.count == linkStore.filteredLinks.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(linkStore.filteredLinks.map(\.id))
                }
            }) {
                let allSelected = selectedIDs.count == linkStore.filteredLinks.count && !linkStore.filteredLinks.isEmpty
                Label(allSelected ? "Deselect All" : "Select All", systemImage: allSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if !selectedIDs.isEmpty {
                Text("\(selectedIDs.count) selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Divider().frame(height: 14)

                Button(action: { showBatchTag = true }) {
                    Label("Tag", systemImage: "tag")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.kPink)
                .popover(isPresented: $showBatchTag, arrowEdge: .bottom) {
                    batchTagPopover
                }

                Button(action: batchArchive) {
                    Label("Archive", systemImage: "archivebox")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: batchDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

            Spacer()

            Button("Done") {
                isSelecting = false
                selectedIDs.removeAll()
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    var batchTagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tag \(selectedIDs.count) links")
                .font(.system(size: 12, weight: .semibold))

            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Add tag...", text: $batchTagInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        addBatchTag(batchTagInput)
                        batchTagInput = ""
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            // Common tags shared by selection
            let selectedLinks = linkStore.links.filter { selectedIDs.contains($0.id) }
            let commonTags = selectedLinks.reduce(into: Set(selectedLinks.first?.tags ?? [])) { result, link in
                result.formIntersection(link.tags)
            }
            if !commonTags.isEmpty {
                Text("Remove tag")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 4) {
                    ForEach(commonTags.sorted(), id: \.self) { tag in
                        Button(action: { removeBatchTag(tag) }) {
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.kPink.opacity(0.15), in: Capsule())
                            .foregroundStyle(.kPink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Existing tags to add
            let available = linkStore.allTags.filter { !commonTags.contains($0) }
            if !available.isEmpty {
                Text("Add tag")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                FlowLayout(spacing: 4) {
                    ForEach(available.prefix(8), id: \.self) { tag in
                        Button(action: { addBatchTag(tag) }) {
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func addBatchTag(_ input: String) {
        let tag = input.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty else { return }
        for id in selectedIDs {
            if let link = linkStore.links.first(where: { $0.id == id }) {
                linkStore.addTag(tag, to: link)
            }
        }
    }

    private func removeBatchTag(_ tag: String) {
        for id in selectedIDs {
            if let index = linkStore.links.firstIndex(where: { $0.id == id }) {
                var tags = linkStore.links[index].tags
                tags.removeAll { $0 == tag }
                linkStore.updateTags(linkStore.links[index], tags: tags)
            }
        }
    }

    private func batchArchive() {
        for id in selectedIDs {
            if let link = linkStore.links.first(where: { $0.id == id }) {
                linkStore.archive(link)
            }
        }
        selectedIDs.removeAll()
    }

    private func batchDelete() {
        for id in selectedIDs {
            if let link = linkStore.links.first(where: { $0.id == id }) {
                linkStore.delete(link)
            }
        }
        selectedIDs.removeAll()
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
                                .foregroundStyle(.kPink)
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
                                    LinkRow(link: link, isSelecting: $isSelecting, selectedIDs: $selectedIDs)
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
            .background(isSelected ? Color.kPink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
                    .foregroundStyle(.kPink)
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
            .background(isSelected ? Color.kPink.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 6))
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
    @Binding var isSelecting: Bool
    @Binding var selectedIDs: Set<UUID>
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var isHovering = false
    @State private var showTagPopover = false
    @State private var tagInput = ""

    var isSelected: Bool { selectedIDs.contains(link.id) }

    var body: some View {
        HStack(spacing: 10) {
            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? .kPink : .secondary)
            } else {
                // Favicon placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: 20, height: 20)
                    .overlay {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
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
                        .foregroundStyle(.kPink.opacity(0.7))
                }
            }

            // Actions on hover
            if isHovering {
                Menu {
                    Button(action: openLink) {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                    Button(action: openInNewTab) {
                        Label("Open in New Tab", systemImage: "plus.rectangle")
                    }

                    Divider()

                    Button(action: {
                        isSelecting = true
                        selectedIDs.insert(link.id)
                    }) {
                        Label("Select", systemImage: "checkmark.circle")
                    }

                    Button(action: { showTagPopover = true }) {
                        Label("Tag", systemImage: "tag")
                    }

                    if link.isArchived {
                        Button(action: { linkStore.unarchive(link) }) {
                            Label("Move to Inbox", systemImage: "tray")
                        }
                    } else {
                        Button(action: { linkStore.archive(link) }) {
                            Label("Archive", systemImage: "archivebox")
                        }
                    }

                    Divider()

                    Button(role: .destructive, action: { linkStore.delete(link) }) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIDs.contains(link.id) {
                    selectedIDs.remove(link.id)
                } else {
                    selectedIDs.insert(link.id)
                }
            } else {
                openLink()
            }
        }
        .onHover { isHovering = $0 }
        .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
            tagPopover
        }
    }

    var tagPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.system(size: 12, weight: .semibold))

            // Current tags
            if !link.tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(link.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .medium))
                            Button(action: {
                                var updated = link.tags
                                updated.removeAll { $0 == tag }
                                linkStore.updateTags(link, tags: updated)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.kPink.opacity(0.15), in: Capsule())
                        .foregroundStyle(.kPink)
                    }
                }
            }

            // Add tag
            HStack {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Add tag...", text: $tagInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        let tag = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
                            .replacingOccurrences(of: "#", with: "")
                        if !tag.isEmpty {
                            linkStore.addTag(tag, to: link)
                            tagInput = ""
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            // Existing tags to pick from
            let available = linkStore.allTags.filter { !link.tags.contains($0) }
            if !available.isEmpty {
                HStack(spacing: 4) {
                    ForEach(available.prefix(6), id: \.self) { tag in
                        Button(action: { linkStore.addTag(tag, to: link) }) {
                            Text("#\(tag)")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 240)
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
