import SwiftUI

struct PulseView: View {
    @EnvironmentObject var pulseEngine: PulseEngine
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var showAPIKeyInput = false
    @State private var apiKeyInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.top, 48)
                    .padding(.bottom, 32)

                if pulseEngine.isLoading {
                    loadingState
                } else if pulseEngine.activeRecommendations.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(pulseEngine.categories.enumerated()), id: \.element) { index, category in
                        if index > 0 {
                            sectionDivider
                        }
                        categorySection(category)
                    }
                }

                if let error = pulseEngine.error {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                footer
                    .padding(.top, 40)
                    .padding(.bottom, 48)
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Masthead

    var masthead: some View {
        VStack(spacing: 8) {
            // Pixel-style decorative dots
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.kPink.opacity(0.4))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.bottom, 4)

            Text("SCOUT")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .tracking(6)

            // Pixel divider
            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.kPink.opacity(0.5) : .clear)
                        .frame(width: 3, height: 2)
                }
            }
            .padding(.vertical, 4)

            if let lastRefreshed = pulseEngine.lastRefreshed {
                Text(lastRefreshed.formatted(.dateTime.year().month(.abbreviated).day()))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category Section

    func categorySection(_ category: String) -> some View {
        let recs = pulseEngine.recommendations(for: category)
        return VStack(alignment: .leading, spacing: 12) {
            // Section header — pixel style
            HStack(spacing: 6) {
                // Pixel block indicator
                Rectangle()
                    .fill(Color.kPink)
                    .frame(width: 6, height: 6)

                Text(category.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .tracking(2)

                // Dotted line
                HStack(spacing: 4) {
                    ForEach(0..<30, id: \.self) { _ in
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 2, height: 2)
                    }
                }
            }
            .padding(.horizontal, 32)

            // Items
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { index, rec in
                    if index > 0 {
                        // Pixel dash separator
                        HStack(spacing: 4) {
                            ForEach(0..<20, id: \.self) { _ in
                                Rectangle()
                                    .fill(.quaternary.opacity(0.5))
                                    .frame(width: 3, height: 1)
                            }
                        }
                        .padding(.horizontal, 32)
                    }
                    ScoutRow(recommendation: rec)
                }
            }
        }
        .padding(.vertical, 20)
    }

    var sectionDivider: some View {
        HStack(spacing: 4) {
            ForEach(0..<60, id: \.self) { i in
                Rectangle()
                    .fill(i % 3 == 0 ? Color.kPink.opacity(0.2) : .clear)
                    .frame(width: 2, height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 48)
    }

    // MARK: - States

    var loadingState: some View {
        VStack(spacing: 12) {
            // Pixel loading animation
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(Color.kPink)
                        .frame(width: 6, height: 6)
                        .opacity(0.3)
                }
            }
            Text("scouting...")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            // Pixel crosshair
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    Color.clear.frame(width: 4, height: 4)
                    Rectangle().fill(.quaternary).frame(width: 4, height: 4)
                    Color.clear.frame(width: 4, height: 4)
                }
                HStack(spacing: 1) {
                    Rectangle().fill(.quaternary).frame(width: 4, height: 4)
                    Rectangle().fill(Color.kPink.opacity(0.5)).frame(width: 4, height: 4)
                    Rectangle().fill(.quaternary).frame(width: 4, height: 4)
                }
                HStack(spacing: 1) {
                    Color.clear.frame(width: 4, height: 4)
                    Rectangle().fill(.quaternary).frame(width: 4, height: 4)
                    Color.clear.frame(width: 4, height: 4)
                }
            }

            Text("nothing to scout yet")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("save some links first (⌘D)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }

    // MARK: - Footer

    var footer: some View {
        VStack(spacing: 8) {
            // Pixel divider
            HStack(spacing: 2) {
                ForEach(0..<40, id: \.self) { i in
                    Rectangle()
                        .fill(i % 2 == 0 ? Color.secondary.opacity(0.2) : Color.clear)
                        .frame(width: 3, height: 2)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Button(action: {
                    Task { await pulseEngine.refresh(links: linkStore.links) }
                }) {
                    Label("refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(pulseEngine.isLoading)

                Text("//")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)

                Text("scouted for you")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text("//")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)

                Button(action: { showAPIKeyInput.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key")
                            .font(.system(size: 9))
                        Text(pulseEngine.hasAPIKey ? "key set" : "add key")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(pulseEngine.hasAPIKey ? Color.secondary : Color.kPink)
                .popover(isPresented: $showAPIKeyInput) {
                    VStack(spacing: 10) {
                        Text("ANTHROPIC API KEY")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 280)
                            .onSubmit {
                                pulseEngine.setAPIKey(apiKeyInput)
                                showAPIKeyInput = false
                            }
                        Button("save") {
                            pulseEngine.setAPIKey(apiKeyInput)
                            showAPIKeyInput = false
                        }
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .buttonStyle(.borderedProminent)
                        .tint(Color.kPink)
                    }
                    .padding(16)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Row

struct ScoutRow: View {
    let recommendation: PulseRecommendation
    @EnvironmentObject var pulseEngine: PulseEngine
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var linkStore: LinkStore
    @State private var isHovering = false

    var isSaved: Bool {
        linkStore.links.contains { $0.url == recommendation.url }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + domain
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(recommendation.title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                Text(recommendation.domain)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            // Description
            Text(recommendation.description)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Why — scout note
            HStack(spacing: 4) {
                Rectangle()
                    .fill(Color.kPink)
                    .frame(width: 3, height: 3)
                Text(recommendation.reason)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Color.kPink.opacity(0.7))
            .padding(.top, 2)

            // Actions
            HStack(spacing: 12) {
                if isHovering {
                    Button(action: openRecommendation) {
                        Label("open", systemImage: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button(action: saveRecommendation) {
                        Label(isSaved ? "saved" : "save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.kPink)
                }

                Spacer()

                Button(action: { pulseEngine.like(recommendation) }) {
                    Image(systemName: recommendation.feedback == .liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(recommendation.feedback == .liked ? Color.green : Color.secondary.opacity(0.3))

                Button(action: { pulseEngine.dislike(recommendation) }) {
                    Image(systemName: recommendation.feedback == .dismissed ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(recommendation.feedback == .dismissed ? Color.red.opacity(0.6) : Color.secondary.opacity(0.3))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(isHovering ? Color.primary.opacity(0.03) : .clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .simultaneousGesture(TapGesture().modifiers(.command).onEnded {
            openInBackground()
        })
        .onTapGesture { openRecommendation() }
    }

    private func openRecommendation() {
        if let url = URL(string: recommendation.url) {
            tabManager.createNewTab(url: url)
            NotificationCenter.default.post(name: .togglePulse, object: nil)
        }
    }

    private func openInBackground() {
        if let url = URL(string: recommendation.url) {
            tabManager.createNewTab(url: url, switchTo: false)
        }
    }

    private func saveRecommendation() {
        linkStore.save(
            url: recommendation.url,
            title: recommendation.title
        )
    }
}
