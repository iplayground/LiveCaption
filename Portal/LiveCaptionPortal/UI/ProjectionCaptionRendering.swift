import AppKit
import SwiftUI

enum ProjectionCaptionVerticalPlacement: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .top:
            L10n.text("caption.projectionVerticalPlacement.top")
        case .bottom:
            L10n.text("caption.projectionVerticalPlacement.bottom")
        }
    }

    static func placement(for rawValue: String) -> ProjectionCaptionVerticalPlacement {
        ProjectionCaptionVerticalPlacement(rawValue: rawValue) ?? .bottom
    }
}

struct ProjectionCaptionTextView: NSViewRepresentable {
    let text: String
    let font: NSFont
    let lineSpacing: CGFloat
    let verticalPlacement: ProjectionCaptionVerticalPlacement

    func makeNSView(context: Context) -> ProjectionCaptionDrawingView {
        ProjectionCaptionDrawingView()
    }

    func updateNSView(_ nsView: ProjectionCaptionDrawingView, context: Context) {
        nsView.text = text
        nsView.font = font
        nsView.lineSpacing = lineSpacing
        nsView.verticalPlacement = verticalPlacement
    }
}

final class ProjectionCaptionDrawingView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .systemFont(ofSize: 32, weight: .semibold) {
        didSet { needsDisplay = true }
    }

    var lineSpacing: CGFloat = 6 {
        didSet { needsDisplay = true }
    }

    var verticalPlacement = ProjectionCaptionVerticalPlacement.bottom {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byClipping
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = .left

        let attributedString = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraphStyle,
            ]
        )

        let textBounds = attributedString.boundingRect(
            with: CGSize(width: bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawHeight = min(ceil(textBounds.height), bounds.height)
        let drawRect = CGRect(
            x: bounds.minX,
            y: drawMinY(drawHeight: drawHeight),
            width: bounds.width,
            height: drawHeight
        )

        attributedString.draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }

    private func drawMinY(drawHeight: CGFloat) -> CGFloat {
        switch verticalPlacement {
        case .top:
            return bounds.minY
        case .bottom:
            return max(bounds.minY, bounds.maxY - drawHeight)
        }
    }
}
