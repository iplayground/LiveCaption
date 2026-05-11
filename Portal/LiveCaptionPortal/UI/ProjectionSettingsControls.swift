import AppKit
import SwiftUI

struct ProjectionInspectorRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
    }
}

struct ProjectionInspectorInlineRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            content
        }
    }
}

struct ProjectionDimensionField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var unit = "pt"
    @FocusState private var isTextFieldFocused: Bool

    private var integerValue: Binding<Int> {
        Binding(
            get: { Int(value.rounded()) },
            set: { value = clamped(Double($0)) }
        )
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField("", value: integerValue, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospacedDigit())
                .frame(width: 64)
                .focused($isTextFieldFocused)
                .onSubmit {
                    value = clamped(value)
                    isTextFieldFocused = false
                }
                .onExitCommand {
                    isTextFieldFocused = false
                }

            Stepper(
                "",
                onIncrement: {
                    value = nextSteppedValue()
                },
                onDecrement: {
                    value = previousSteppedValue()
                }
            )
                .labelsHidden()

            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func nextSteppedValue() -> Double {
        let currentValue = clamped(value)
        let nextMultiple = ceil(currentValue / step) * step
        let steppedValue = isMultiple(currentValue) ? currentValue + step : nextMultiple
        return clamped(steppedValue)
    }

    private func previousSteppedValue() -> Double {
        let currentValue = clamped(value)
        let previousMultiple = floor(currentValue / step) * step
        let steppedValue = isMultiple(currentValue) ? currentValue - step : previousMultiple
        return clamped(steppedValue)
    }

    private func isMultiple(_ value: Double) -> Bool {
        abs(value.truncatingRemainder(dividingBy: step)) < 0.0001
    }
}

struct ProjectionCaptionFontChoice: Identifiable {
    static let systemID = "system"

    private static let commonChoices: [ProjectionCaptionFontChoice] = [
        ProjectionCaptionFontChoice(id: systemID, familyName: nil, localizedNameKey: "caption.projectionFont.system"),
        ProjectionCaptionFontChoice(id: "pingfang-tc", familyName: "PingFang TC", localizedNameKey: "caption.projectionFont.pingFangTC"),
        ProjectionCaptionFontChoice(id: "hiragino-sans", familyName: "Hiragino Sans", localizedNameKey: "caption.projectionFont.hiraginoSans"),
        ProjectionCaptionFontChoice(id: "apple-sd-gothic-neo", familyName: "Apple SD Gothic Neo", localizedNameKey: "caption.projectionFont.appleSDGothicNeo"),
        ProjectionCaptionFontChoice(id: "helvetica-neue", familyName: "Helvetica Neue", localizedNameKey: "caption.projectionFont.helveticaNeue")
    ]

    let id: String
    let familyName: String?
    let localizedNameKey: String

    var localizedName: String {
        L10n.text(localizedNameKey)
    }

    static var availableChoices: [ProjectionCaptionFontChoice] {
        let availableFamilies = Set(NSFontManager.shared.availableFontFamilies)
        return commonChoices.filter { choice in
            guard let familyName = choice.familyName else {
                return true
            }

            return availableFamilies.contains(familyName)
        }
    }

    static func choice(for id: String) -> ProjectionCaptionFontChoice {
        availableChoices.first { $0.id == id } ?? commonChoices[0]
    }
}
