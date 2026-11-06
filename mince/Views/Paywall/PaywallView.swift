import StoreKit
import SwiftUI

/// S33: mince+ plans, purchase and restore.
struct PaywallView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = "mince.plus.annual"

    private let perks: [(String, String)] = [
        ("camera", "Log meals from a photo"), ("mic", "Log by voice and Siri"), ("link", "Import recipes from any website"),
        ("calendar", "Different macros for training and rest days"), ("repeat", "Foods that add themselves every day"),
        ("timer", "Fasting timer with schedules"), ("clock", "Times on diary entries"), ("chart.xyaxis.line", "Unlimited history, custom charts and scores"),
        ("sparkle.magnifyingglass", "Find the best foods for any nutrient"), ("heart.text.square", "Track your own biometrics"),
        ("square.and.arrow.up", "PDF reports and data export"), ("person.2", "Share foods and recipes"),
    ]

    var body: some View {
        let store = app.store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        PlusBadge()
                        Text("Get more from every meal you log").font(Theme.Fonts.display)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        ForEach(perks, id: \.1) { symbol, text in
                            Label(text, systemImage: symbol).font(Theme.Fonts.body)
                        }
                    }
                    .card()

                    if store.products.isEmpty {
                        if let e = store.errorMessage { Text(e).foregroundStyle(Theme.Colors.danger) } else { ProgressView().frame(maxWidth: .infinity) }
                    } else {
                        ForEach(store.products, id: \.id) { product in
                            Button { selected = product.id } label: { planCard(product, isSelected: selected == product.id) }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected == product.id ? .isSelected : [])
                        }
                    }

                    if let e = store.errorMessage, !store.products.isEmpty { Text(e).font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.danger) }

                    Button(app.hasPlus ? "You're on mince+" : "Continue") {
                        guard let product = store.products.first(where: { $0.id == selected }), let uid = app.userId else { return }
                        Task {
                            if await store.purchase(product, userId: uid) {
                                await app.refreshPlus()
                                await app.refreshMacroSchedule()
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.minced(.plus, loading: store.isPurchasing))
                    .disabled(store.products.isEmpty || store.isPurchasing || app.hasPlus)

                    HStack {
                        Button("Restore purchases") { Task { await store.restore(); await app.refreshPlus() } }
                        Spacer()
                        Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Link("Privacy", destination: AppLinks.privacy)
                    }
                    .font(Theme.Fonts.footnote)

                    Text("Renews automatically until cancelled. Cancel any time in your App Store account settings.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textMuted)
                }
                .padding(Theme.Space.md)
            }
            .background(Theme.Colors.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
            .task { if store.products.isEmpty { await store.load() } }
        }
    }

    private func planCard(_ p: Product, isSelected: Bool) -> some View {
        let annual = p.subscription?.subscriptionPeriod.unit == .year
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(annual ? "Yearly" : "Monthly").font(Theme.Fonts.heading)
                if annual {
                    Text("\((p.price / 12).formatted(p.priceFormatStyle)) a month, billed yearly").font(Theme.Fonts.footnote).foregroundStyle(Theme.Colors.textMuted)
                }
            }
            Spacer()
            Text(p.displayPrice).font(Theme.Fonts.heading)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.borderInput)
        }
        .padding(Theme.Space.md)
        .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(isSelected ? Theme.Colors.accent : Theme.Colors.border, lineWidth: isSelected ? 2 : 1) }
    }
}

/// Public URLs. Replace the privacy policy placeholder before release (replica-launch writes the page).
enum AppLinks {
    static let privacy = URL(string: "https://example.com/mince/privacy")!
}
