import SwiftUI

struct PulseView: View {
    @EnvironmentObject var pulseEngine: PulseEngine
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Masthead
                masthead
                    .padding(.top, 48)
                    .padding(.bottom, 32)

                if pulseEngine.isLoading {
                    loadingState
                } else if pulseEngine.activeRecommendations.isEmpty {
                    emptyState
                } else {
                    // Newsletter sections by category
                    ForEach(Array(pulseEngine.categories.enumerated()), id: \.element) { index, category in
                        if index > 0 {
                            sectionDivider
                        }
                        categorySection(category)
                    }
                }

                if let error = pulseEngine.error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                }

                // Footer
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
        VStack(spacing: 6) {
            Text("PULSE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.kPink)
                .tracking(4)

            Text("Your Weekly Digest")
                .font(.system(size: 28, weight: .light, design: .serif))
                .foregroundStyle(.primary)

            if let lastRefreshed = pulseEngine.lastRefreshed {
                Text(lastRefreshed.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }

            // Thin rule under masthead
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
                .padding(.top, 16)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Category Section

    func categorySection(_ category: String) -> some View {
        let recs = pulseEngine.recommendations(for: category)
        return VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(category.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.kPink)
                    .tracking(2)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 1)
            }
            .padding(.horizontal, 32)

            // Items
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recs.enumerated()), id: \.element.id) { index, rec in
                    if index > 0 {
                        Rectangle()
                            .fill(.quaternary.opacity(0.5))
                            .frame(height: 1)
                            .padding(.horizontal, 32)
                    }
                    PulseRow(recommendation: rec)
                }
            }
        }
        .padding(.vertical, 20)
    }

    var sectionDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.quaternary).frame(height: 1)
            Image(systemName: "diamond.fill")
                .font(.system(size: 4))
                .foregroundStyle(.quaternary)
            Rectangle().fill(.quaternary).frame(height: 1)
        }
        .padding(.horizontal, 48)
    }

    // MARK: - States

    var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Curating this week's picks...")
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(.secondary)
            Text("Save some links (⌘D) and Pulse will learn what to recommend.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(60)
    }

    // MARK: - Footer

    var footer: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(.quaternary)
                .frame(height: 1)
                .padding(.horizontal, 32)

            HStack(spacing: 16) {
                Button(action: {
                    Task { await pulseEngine.refresh(links: linkStore.links) }
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(pulseEngine.isLoading)

                Text("·")
                    .foregroundStyle(.quaternary)

                Text("Curated by Pulse for you")
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(.tertiary)
                    .italic()
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Row

struct PulseRow: View {
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
            // Title as link
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(recommendation.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)

                Text(recommendation.domain)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            // Description
            Text(recommendation.description)
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // Why — editorial note
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                Text(recommendation.reason)
                    .font(.system(size: 11, weight: .medium))
                    .italic()
            }
            .foregroundStyle(Color.kPink.opacity(0.7))
            .padding(.top, 2)

            // Actions — always show feedback, show read/save on hover
            HStack(spacing: 12) {
                if isHovering {
                    Button(action: openRecommendation) {
                        Label("Read", systemImage: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button(action: saveRecommendation) {
                        Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 10, weight: .medium))
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
            title: recommendation.title,
            tags: recommendation.tags
        )
    }
}
