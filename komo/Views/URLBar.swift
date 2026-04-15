import SwiftUI

struct NavButtons: View {
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        HStack(spacing: 2) {
            NavButton(icon: "chevron.left", enabled: tabManager.selectedTab?.canGoBack ?? false) {
                tabManager.selectedTab?.goBack()
            }
            NavButton(icon: "chevron.right", enabled: tabManager.selectedTab?.canGoForward ?? false) {
                tabManager.selectedTab?.goForward()
            }
            NavButton(icon: tabManager.selectedTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                      enabled: true) {
                if tabManager.selectedTab?.isLoading == true {
                    tabManager.selectedTab?.webView.stopLoading()
                } else {
                    tabManager.selectedTab?.reload()
                }
            }
        }
    }
}

struct URLPill: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var urlText: String = ""
    @State private var isEditing: Bool = false
    @FocusState private var isURLFocused: Bool

    var body: some View {
        if isEditing {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search or enter URL", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isURLFocused)
                    .onSubmit {
                        navigateTo(urlText)
                        isEditing = false
                    }
                    .onExitCommand {
                        isEditing = false
                        isURLFocused = false
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())
            .frame(maxWidth: 500)
            .onReceive(NotificationCenter.default.publisher(for: .focusURLBar)) { _ in
                // already editing, just refocus
            }
            .onChange(of: tabManager.selectedTabID) {
                isEditing = false
            }
        } else {
            Button(action: startEditing) {
                HStack(spacing: 4) {
                    Image(systemName: isSecure ? "lock.fill" : "globe")
                        .font(.system(size: 10))
                        .foregroundColor(isSecure ? .green : .gray)

                    Text(displayURL)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.3), in: Capsule())
            }
            .buttonStyle(.plain)
            .onReceive(NotificationCenter.default.publisher(for: .focusURLBar)) { _ in
                startEditing()
            }
            .onChange(of: tabManager.selectedTabID) {
                isEditing = false
            }
        }
    }

    private var isSecure: Bool {
        tabManager.selectedTab?.url?.scheme == "https"
    }

    private var displayURL: String {
        guard let url = tabManager.selectedTab?.url else { return "New Tab" }
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
    }

    private func startEditing() {
        urlText = tabManager.selectedTab?.url?.absoluteString ?? ""
        if tabManager.selectedTab?.url == nil {
            urlText = ""
        }
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isURLFocused = true
        }
    }

    private func navigateTo(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url: URL?

        if trimmed.contains(".") && !trimmed.contains(" ") {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                url = URL(string: trimmed)
            } else {
                url = URL(string: "https://\(trimmed)")
            }
        } else {
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            url = URL(string: "https://duckduckgo.com/?q=\(encoded)")
        }

        if let url = url {
            if let tab = tabManager.selectedTab {
                tab.load(url)
            } else {
                tabManager.createNewTab(url: url)
            }
        }

        isURLFocused = false
    }
}

struct NavButton: View {
    let icon: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .primary : .quaternary)
        .disabled(!enabled)
    }
}
