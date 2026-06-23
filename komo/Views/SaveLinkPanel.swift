import SwiftUI

struct SaveLinkPanel: View {
    @EnvironmentObject var linkStore: LinkStore
    @Binding var isPresented: Bool
    let url: String
    let title: String

    @State private var editTitle: String = ""
    @State private var tagInput: String = ""
    @State private var tags: [String] = []
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.kPink)
                Text("Save Link")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // URL preview
            Text(url)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)

            // Title
            TextField("Title", text: $editTitle)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            // Tags
            VStack(alignment: .leading, spacing: 6) {
                // Current tags
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text("#\(tag)")
                                    .font(.system(size: 11, weight: .medium))
                                Button(action: { tags.removeAll { $0 == tag } }) {
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

                // Tag input
                HStack {
                    Image(systemName: "tag")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("Add tag...", text: $tagInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { addTag() }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                // Suggested tags
                let suggestions = linkStore.suggestTags(for: url).filter { !tags.contains($0) }
                if !suggestions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button(action: { tags.append(tag) }) {
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

            // Notes
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .lineLimit(2...4)

            // Actions
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { saveLink() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.kPink)
            }
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            editTitle = title
            tags = linkStore.suggestTags(for: url)
        }
    }

    private func addTag() {
        let tag = tagInput.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "#", with: "")
        guard !tag.isEmpty, !tags.contains(tag) else { return }
        tags.append(tag)
        tagInput = ""
    }

    private func saveLink() {
        addTag() // capture any pending tag input
        linkStore.save(url: url, title: editTitle, tags: tags, notes: notes)
        isPresented = false
    }
}

// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x)
            totalHeight = y + rowHeight
        }

        return (positions, CGSize(width: totalWidth, height: totalHeight))
    }
}
