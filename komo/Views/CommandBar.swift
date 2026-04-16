import SwiftUI

struct CommandBar: View {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var linkStore: LinkStore
    @Binding var isPresented: Bool
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @State private var activeFolder: TabFolder? = nil
    @State private var activeLinkTag: String? = nil
    @FocusState private var isFocused: Bool

    var sections: [CommandSection] {
        if let folder = activeFolder {
            return folderContents(folder)
        }
        if let tag = activeLinkTag {
            return tagContents(tag)
        }
        return mainResults()
    }

    var flatResults: [CommandResult] {
        sections.flatMap { $0.items }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb + search
            HStack(spacing: 6) {
                if activeFolder != nil || activeLinkTag != nil {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                if let folder = activeFolder {
                    Text(folder.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.kPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.kPink.opacity(0.1), in: Capsule())
                    Text("/")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                } else if let tag = activeLinkTag {
                    Text("#\(tag)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.kPink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.kPink.opacity(0.1), in: Capsule())
                    Text("/")
                        .font(.system(size: 12))
                        .foregroundStyle(.quaternary)
                }

                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit { executeSelected() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if !sections.isEmpty {
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sections) { section in
                            if let label = section.label {
                                Text(label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }

                            ForEach(Array(section.items.enumerated()), id: \.offset) { itemIndex, result in
                                let globalIndex = globalIndexOf(section: section, itemIndex: itemIndex)
                                CommandResultRow(result: result, isSelected: globalIndex == selectedIndex)
                                    .onTapGesture { execute(result) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .frame(width: 480)
        .onAppear {
            isFocused = true
            selectedIndex = 0
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(flatResults.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if activeFolder != nil || activeLinkTag != nil {
                goBack()
            } else {
                isPresented = false
            }
            return .handled
        }
        .onKeyPress(.delete) {
            if query.isEmpty && (activeFolder != nil || activeLinkTag != nil) {
                goBack()
                return .handled
            }
            return .ignored
        }
    }

    private var placeholder: String {
        if activeFolder != nil { return "Search in folder..." }
        if activeLinkTag != nil { return "Search in tag..." }
        return "Search tabs, links, or enter URL..."
    }

    private func goBack() {
        activeFolder = nil
        activeLinkTag = nil
        query = ""
        selectedIndex = 0
    }

    // MARK: - Main results (no folder/tag selected)

    private func mainResults() -> [CommandSection] {
        let q = query.lowercased()
        var sections: [CommandSection] = []

        // Active tabs (exclude empty tabs)
        let matchingTabs = tabManager.tabs.filter { tab in
            tab.url != nil && (q.isEmpty || tab.title.lowercased().contains(q) || (tab.url?.absoluteString.lowercased().contains(q) ?? false))
        }
        if !matchingTabs.isEmpty {
            sections.append(CommandSection(
                label: "Open Tabs",
                items: matchingTabs.prefix(5).map { .tab($0) }
            ))
        }

        // Folders (browseable)
        let matchingFolders = tabManager.folders.filter { folder in
            q.isEmpty || folder.name.lowercased().contains(q)
        }
        if !matchingFolders.isEmpty {
            sections.append(CommandSection(
                label: "Folders",
                items: matchingFolders.map { .folder($0) }
            ))
        }

        // Link tags (browseable)
        let matchingTags = linkStore.allTags.filter { tag in
            q.isEmpty || tag.lowercased().contains(q)
        }
        if !matchingTags.isEmpty && !matchingTags.isEmpty {
            sections.append(CommandSection(
                label: "Saved Link Tags",
                items: matchingTags.prefix(5).map { .linkTag($0) }
            ))
        }

        // Saved links (direct matches)
        if !q.isEmpty {
            let matchingLinks = linkStore.links.filter { link in
                link.title.lowercased().contains(q) || link.url.lowercased().contains(q)
            }
            if !matchingLinks.isEmpty {
                sections.append(CommandSection(
                    label: "Saved Links",
                    items: matchingLinks.prefix(5).map { .savedLink($0) }
                ))
            }
        }

        // Navigate / search action
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            sections.append(CommandSection(
                label: nil,
                items: [.navigate(query)]
            ))
        }

        return sections
    }

    // MARK: - Folder contents

    private func folderContents(_ folder: TabFolder) -> [CommandSection] {
        let q = query.lowercased()
        let folderTabs = folder.tabIDs.compactMap { tabManager.tab(for: $0) }.filter { tab in
            q.isEmpty || tab.title.lowercased().contains(q) || (tab.url?.absoluteString.lowercased().contains(q) ?? false)
        }

        var sections: [CommandSection] = []
        if !folderTabs.isEmpty {
            sections.append(CommandSection(
                label: "\(folder.name)",
                items: folderTabs.map { .tab($0) }
            ))
        }
        return sections
    }

    // MARK: - Tag contents

    private func tagContents(_ tag: String) -> [CommandSection] {
        let q = query.lowercased()
        let tagLinks = linkStore.links.filter { link in
            link.tags.contains(tag) && (q.isEmpty || link.title.lowercased().contains(q) || link.url.lowercased().contains(q))
        }

        var sections: [CommandSection] = []
        if !tagLinks.isEmpty {
            sections.append(CommandSection(
                label: "#\(tag)",
                items: tagLinks.map { .savedLink($0) }
            ))
        }
        return sections
    }

    // MARK: - Helpers

    private func globalIndexOf(section: CommandSection, itemIndex: Int) -> Int {
        var index = 0
        for s in sections {
            if s.id == section.id {
                return index + itemIndex
            }
            index += s.items.count
        }
        return 0
    }

    private func executeSelected() {
        guard selectedIndex < flatResults.count else { return }
        execute(flatResults[selectedIndex])
    }

    private func execute(_ result: CommandResult) {
        switch result {
        case .tab(let tab):
            tabManager.selectTab(tab)
            isPresented = false
        case .savedLink(let link):
            if let url = URL(string: link.url) {
                tabManager.createNewTab(url: url)
            }
            isPresented = false
        case .folder(let folder):
            activeFolder = folder
            activeLinkTag = nil
            query = ""
            selectedIndex = 0
        case .linkTag(let tag):
            activeLinkTag = tag
            activeFolder = nil
            query = ""
            selectedIndex = 0
        case .navigate(let input):
            let trimmed = input.trimmingCharacters(in: .whitespaces)
            let url: URL?
            if trimmed.contains(".") && !trimmed.contains(" ") {
                url = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: "https://\(trimmed)")
            } else {
                let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
                url = URL(string: "https://duckduckgo.com/?q=\(encoded)")
            }
            if let url = url {
                tabManager.createNewTab(url: url)
            }
            isPresented = false
        }
    }
}

// MARK: - Data types

struct CommandSection: Identifiable {
    let id = UUID()
    let label: String?
    let items: [CommandResult]
}

enum CommandResult {
    case tab(Tab)
    case savedLink(SavedLink)
    case folder(TabFolder)
    case linkTag(String)
    case navigate(String)
}

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(badge)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            if isEntereable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.kPink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch result {
        case .tab: return "globe"
        case .savedLink: return "bookmark"
        case .folder: return "folder.fill"
        case .linkTag: return "number"
        case .navigate: return "magnifyingglass"
        }
    }

    private var iconColor: Color {
        switch result {
        case .folder: return .blue
        case .linkTag: return .kPink
        default: return .secondary
        }
    }

    private var title: String {
        switch result {
        case .tab(let tab): return tab.title
        case .savedLink(let link): return link.title
        case .folder(let folder): return folder.name
        case .linkTag(let tag): return "#\(tag)"
        case .navigate(let query): return query
        }
    }

    private var subtitle: String? {
        switch result {
        case .tab(let tab): return tab.url?.host
        case .savedLink(let link): return URL(string: link.url)?.host
        case .folder(let folder): return "\(folder.tabIDs.count) tabs"
        case .linkTag: return nil
        case .navigate: return nil
        }
    }

    private var badge: String {
        switch result {
        case .tab: return "Tab"
        case .savedLink: return "Saved"
        case .folder: return "Folder"
        case .linkTag: return "Tag"
        case .navigate: return "Go"
        }
    }

    private var isEntereable: Bool {
        switch result {
        case .folder, .linkTag: return true
        default: return false
        }
    }
}
