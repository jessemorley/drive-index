//
//  TagInputView.swift
//  DriveIndex
//
//  A reusable tag input component that displays items as removable chips
//  and allows adding new items by typing and pressing comma or return.
//

import SwiftUI

struct TagInputView: View {
    @Binding var tags: [String]
    var placeholder: String = "Type and press comma to add..."

    @State private var currentInput: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowLayout(spacing: 4) {
                // Display existing tags
                ForEach(tags, id: \.self) { tag in
                    TagChip(text: tag, onRemove: {
                        removeTag(tag)
                    })
                }

                // Input field for new tags
                TextField(tags.isEmpty ? placeholder : "", text: $currentInput)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 120, maxWidth: .infinity)
                    .focused($isInputFocused)
                    .onSubmit {
                        addCurrentTag()
                    }
                    .onChange(of: currentInput) { _, newValue in
                        // Check for comma to add tag
                        if newValue.contains(",") {
                            addCurrentTag()
                        }
                    }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ponytail: SwiftUI has no token field; drawn to match a bordered text field
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            .onTapGesture {
                isInputFocused = true
            }
        }
    }

    private func addCurrentTag() {
        // Remove commas and trim whitespace
        let trimmed = currentInput
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Only add non-empty, non-duplicate tags
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            tags.append(trimmed)
        }

        currentInput = ""
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
    }
}

struct TagChip: View {
    let text: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(text)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(text)")
        }
        .padding(4)
        .background(.quaternary, in: .rect(cornerRadius: 4))
    }
}

/// A layout that arranges views in a flowing, wrapping pattern
struct FlowLayout: Layout {
    var spacing: CGFloat = 8          // horizontal spacing
    var lineSpacing: CGFloat = 6     // vertical spacing between lines

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing,
            lineSpacing: lineSpacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing,
            lineSpacing: lineSpacing
        )

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat, lineSpacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                // wrap to next line if needed
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + lineSpacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                sizes.append(size)

                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(
                width: maxWidth,
                height: y + lineHeight
            )
        }
    }
}


#Preview {
    VStack(spacing: 20) {
        TagInputView(
            tags: .constant(["node_modules", ".git", "Library", "System Volume Information"]),
            placeholder: "Add directory..."
        )

        TagInputView(
            tags: .constant([".tmp", ".cache", ".DS_Store"]),
            placeholder: "Add extension..."
        )
    }
    .padding()
    .frame(width: 400)
}
