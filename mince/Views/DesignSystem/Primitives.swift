import SwiftUI

// Shared UI primitives. Specs: replica/design/components.md.

// MARK: - Buttons

struct MinceButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, plus }
    var kind: Kind = .primary
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Theme.Space.xs) {
            if isLoading { ProgressView().tint(foreground) }
            configuration.label
        }
        .font(Theme.Fonts.heading)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            if kind == .secondary {
                RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.Colors.borderInput)
            }
        }
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
        .accessibilityHint(isLoading ? Text("Loading") : Text(""))
    }

    private var foreground: Color {
        switch kind {
        case .primary: Theme.Colors.onAccent
        case .secondary: Theme.Colors.text
        case .destructive: Theme.Colors.danger
        case .plus: Theme.Colors.onPlus
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Theme.Colors.accent
        case .secondary, .destructive: Theme.Colors.surface
        case .plus: Theme.Colors.plus
        }
    }
}

extension ButtonStyle where Self == MinceButtonStyle {
    static var minced: MinceButtonStyle { MinceButtonStyle() }
    static func minced(_ kind: MinceButtonStyle.Kind, loading: Bool = false) -> MinceButtonStyle {
        MinceButtonStyle(kind: kind, isLoading: loading)
    }
}

// MARK: - mince+ badge

struct PlusBadge: View {
    var body: some View {
        Label("mince+", systemImage: "lock.fill")
            .font(Theme.Fonts.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, Theme.Space.xs)
            .padding(.vertical, 2)
            .foregroundStyle(Theme.Colors.onPlus)
            .background(Theme.Colors.plus, in: Capsule())
            .accessibilityLabel("mince+ feature")
    }
}

// MARK: - Nutrient / macro bar

struct NutrientBar: View {
    let name: String
    let amount: Double
    let unit: String
    var target: Double?
    var max: Double?
    var tint: Color = Theme.Colors.accent

    private enum Status { case noTarget, below, inRange, over }

    private var status: Status {
        if let max, amount > max { return .over }
        guard let target, target > 0 else { return .noTarget }
        return amount >= target ? .inRange : .below
    }

    private var fraction: Double {
        guard let target, target > 0 else { return 0 }
        return min(amount / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            // Side by side when it fits; stacked (and wrapping) at large text sizes instead of truncating.
            ViewThatFits(in: .horizontal) {
                HStack { nameLabel; Spacer(minLength: Theme.Space.xs); valueLabel }
                VStack(alignment: .leading, spacing: 2) { nameLabel; valueLabel }
            }
            if status != .noTarget {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.Colors.track)
                        Capsule().fill(status == .over ? Theme.Colors.warning : tint)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: Theme.Layout.barHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var nameLabel: some View {
        HStack {
            Text(name).font(Theme.Fonts.body).fixedSize(horizontal: false, vertical: true)
            if status == .over {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.warning)
            }
        }
    }

    private var valueLabel: some View {
        Text(valueText).font(Theme.Fonts.footnote.monospacedDigit()).foregroundStyle(Theme.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: String {
        let a = amount.formatted(.number.precision(.fractionLength(0...1)))
        guard let target else { return "\(a) \(unit)" }
        let pct = Int((amount / Swift.max(target, 0.0001) * 100).rounded())
        return "\(a) / \(target.formatted(.number.precision(.fractionLength(0...1)))) \(unit) · \(pct)%"
    }

    private var accessibilityText: String {
        var s = "\(name), \(valueText.replacingOccurrences(of: " · ", with: ", "))"
        if status == .over { s += ", over limit" }
        return s
    }
}

// MARK: - Energy ring

struct EnergyRing: View {
    let consumed: Double
    let target: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var remaining: Double { target - consumed }
    private var isOver: Bool { consumed > target * 1.05 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.track, lineWidth: Theme.Layout.ringLine)
            Circle()
                .trim(from: 0, to: target > 0 ? min(consumed / target, 1) : 0)
                .stroke(isOver ? Theme.Colors.warning : Theme.Colors.energy,
                        style: StrokeStyle(lineWidth: Theme.Layout.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : Theme.Motion.base, value: consumed)
            VStack(spacing: 0) {
                Text(abs(remaining).formatted(.number.precision(.fractionLength(0))))
                    .font(Theme.Fonts.metric)
                Text(isOver ? "kcal over" : "kcal left")
                    .font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
            }
        }
        .frame(width: Theme.Layout.ringSize, height: Theme.Layout.ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(consumed)) of \(Int(target)) calories eaten, \(Int(abs(remaining))) \(isOver ? "over" : "remaining")")
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var hint: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(Theme.Colors.textMuted)
            Text(title).font(Theme.Fonts.heading)
            if let hint {
                Text(hint).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.minced(.secondary)).padding(.top, Theme.Space.xs)
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity)
    }
}
