import SwiftUI

/// Keeps the same editor alive and the controls on the bottom edge while the field expands above them.
struct ComposerLayout: Layout {
    var expansion: CGFloat
    var spacing: CGFloat = 8

    var animatableData: CGFloat {
        get { expansion }
        set { expansion = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let sizes = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: sizes.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(width: bounds.width, subviews: subviews)
        let bottom = bounds.maxY
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bottom), anchor: .bottomLeading,
                          proposal: ProposedViewSize(sizes.leading))
        subviews[1].place(at: CGPoint(x: bounds.minX + sizes.fieldInset, y: bottom - sizes.fieldRise),
                          anchor: .bottomLeading, proposal: ProposedViewSize(sizes.field))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bottom), anchor: .bottomTrailing,
                          proposal: ProposedViewSize(sizes.trailing))
        // Keep shortcut widths out of the compact editor measurement so the editor can
        // interpolate smoothly on focus, even on widths that could not fit all five views inline.
        subviews[3].place(at: CGPoint(x: bounds.minX + sizes.leading.width, y: bottom), anchor: .bottomLeading,
                          proposal: .unspecified)
        subviews[4].place(at: CGPoint(x: bounds.maxX - sizes.trailing.width, y: bottom), anchor: .bottomTrailing,
                          proposal: .unspecified)
    }

    private func measure(width: CGFloat, subviews: Subviews)
        -> (leading: CGSize, field: CGSize, trailing: CGSize, fieldInset: CGFloat, fieldRise: CGFloat, height: CGFloat) {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let inlineWidth = width - leading.width - trailing.width - 2 * spacing
        let progress = inlineWidth < 140 ? 1 : min(1, max(0, expansion))
        let fieldWidth = inlineWidth + (width - 16 - inlineWidth) * progress
        let field = subviews[1].sizeThatFits(ProposedViewSize(width: fieldWidth, height: nil))
        let controlsHeight = max(leading.height, trailing.height)
        let inlineRise = max(0, (controlsHeight - field.height) / 2)
        let fieldRise = inlineRise + (controlsHeight + spacing - inlineRise) * progress
        return (leading, field, trailing, (leading.width + spacing) * (1 - progress) + 8 * progress, fieldRise,
                max(controlsHeight, field.height + fieldRise))
    }
}


/// Reveals the controls as the editor clears their row, on the same animation as the layout.
struct ComposerShortcutReveal: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let reveal = min(1, max(0, (progress - 0.35) / 0.65))
        content
            .opacity(Double(reveal))
            .scaleEffect(0.94 + 0.06 * reveal)
    }
}


/// The microphone capsule and its yoke, with a short stem and no horizontal foot.
struct ComposerMicrophoneOutline: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 24, y: rect.minY + rect.height * y / 24)
        }

        let capsule = CGRect(origin: point(8.4, 1.8), size: CGSize(width: rect.width * 0.3, height: rect.height * 0.55))
        var outline = Path(roundedRect: capsule, cornerRadius: capsule.width / 2)
        outline.move(to: point(4.8, 10.7))
        outline.addLine(to: point(4.8, 12))
        outline.addQuadCurve(to: point(12, 19.2), control: point(4.8, 19.2))
        outline.addQuadCurve(to: point(19.2, 12), control: point(19.2, 19.2))
        outline.addLine(to: point(19.2, 10.7))
        outline.move(to: point(12, 19.2))
        outline.addLine(to: point(12, 22.2))
        return outline
    }
}
