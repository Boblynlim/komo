import SwiftUI

struct PulseView: View {
    @EnvironmentObject var pulseEngine: PulseEngine
    @EnvironmentObject var linkStore: LinkStore
    @EnvironmentObject var tabManager: TabManager
    @State private var showAPIKeyInput = false
    @State private var apiKeyInput = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                header
                    .padding(.top, 40)

                if !pulseEngine.hasAPIKey {
                    apiKeyPrompt
                } else if pulseEngine.isLoading {
                    loadingState
                } else if pulseEngine.activeRecommendations.isEmpty {
                    emptyState
                } else {
                    // Recommendation cards
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(pulseEngine.activeRecommendations) { rec in
                            PulseCard(recommendation: rec)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                if let error = pulseEngine.error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding()
                }

                Spacer(minLength: 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Pulse")
                    .font(.system(size: 28, weight: .light, design: .rounded))

                if pulseEngine.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }

            if let lastRefreshed = pulseEngine.lastRefreshed {
                Text("Updated \(lastRefreshed.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Button(action: refreshPulse) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(pulseEngine.isLoading)

                Button(action: { showAPIKeyInput.toggle() }) {
                    Image(systemName: "key")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .popover(isPresented: $showAPIKeyInput) {
                    VStack(spacing: 10) {
                        Text("Claude API Key")
                            .font(.system(size: 12, weight: .semibold))
                        SecureField("sk-ant-...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                            .onSubmit {
                                pulseEngine.setAPIKey(apiKeyInput)
                                showAPIKeyInput = false
                            }
                        Button("Save") {
                            pulseEngine.setAPIKey(apiKeyInput)
                            showAPIKeyInput = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                    .padding(16)
                }
            }
            .padding(.top, 4)
        }
    }

    var apiKeyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.purple.opacity(0.5))

            Text("Pulse needs a Claude API key to find you cool stuff")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            SecureField("sk-ant-...", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit {
                    pulseEngine.setAPIKey(apiKeyInput)
                    refreshPulse()
                }

            Button("Connect") {
                pulseEngine.setAPIKey(apiKeyInput)
                refreshPulse()
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(apiKeyInput.isEmpty)
        }
        .padding(40)
    }

    var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding things you'd like...")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)

            if linkStore.links.isEmpty {
                Text("Save some links first")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Pulse learns from your saved links to recommend new stuff.\nPress \u{2318}D to save pages you like.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Ready to discover")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("Generate Recommendations") {
                    refreshPulse()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
        }
        .padding(40)
    }

    private func refreshPulse() {
        Task {
            await pulseEngine.refresh(links: linkStore.links)
        }
    }
}

struct PulseCard: View {
    let recommendation: PulseRecommendation
    @EnvironmentObject var pulseEngine: PulseEngine
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var linkStore: LinkStore
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Domain
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text(recommendation.domain)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
            }

            // Title
            Text(recommendation.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Description
            Text(recommendation.description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // Reason
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple)
                Text(recommendation.reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.purple.opacity(0.8))
                    .lineLimit(1)
            }

            // Tags
            HStack(spacing: 4) {
                ForEach(recommendation.tags.prefix(3), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
            }

            // Actions
            if isHovering || recommendation.feedback == .liked {
                HStack(spacing: 8) {
                    Button(action: { openRecommendation() }) {
                        Label("Open", systemImage: "arrow.up.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)

                    Button(action: { saveRecommendation() }) {
                        Label("Save", systemImage: "bookmark")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.purple)

                    Spacer()

                    Button(action: { pulseEngine.like(recommendation) }) {
                        Image(systemName: recommendation.feedback == .liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(recommendation.feedback == .liked ? .green : .secondary)

                    Button(action: { pulseEngine.dismiss(recommendation) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(recommendation.feedback == .liked ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(isHovering ? 0.1 : 0.04), radius: isHovering ? 8 : 4, y: 2)
        .onHover { isHovering = $0 }
        .onTapGesture { openRecommendation() }
    }

    private func openRecommendation() {
        if let url = URL(string: recommendation.url) {
            tabManager.createNewTab(url: url)
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
