import SwiftUI

/// Requests HealthKit read authorization and pulls a first 28-day rollup.
/// After the initial pull the app's supposed to top up nightly — but the
/// simple "user opens Settings and taps HealthKit" flow is enough for v1;
/// background delivery is a follow-up.
struct HealthKitSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let aggregator = HealthKitAggregator.shared
    private let repo = HealthDaysRepository()

    @State private var state: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case requesting
        case syncing(count: Int?)
        case done(days: Int)
        case failed(String)
    }

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("BODY DATA")
                        .font(Font.Soma.sectionTag)
                        .tracking(3)
                        .foregroundStyle(Color.ink)
                }
                .padding(.top, Theme.Spacing.s)

                Text("HealthKit — read only")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)

                Text("Soma reads steps, sleep, resting heart rate, and HRV to look for gentle correlations. Raw HealthKit samples stay on your phone — only a daily summary is stored.")
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                statusRow

                Spacer(minLength: 0)

                actionRow
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .idle:
            Text(aggregator.isAvailable
                 ? "not yet connected — tap “connect” to allow."
                 : "HealthKit isn't available on this device.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
        case .requesting:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().controlSize(.small).tint(Color.inkSoft)
                Text("waiting on permission…")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
            }
        case .syncing:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView().controlSize(.small).tint(Color.inkSoft)
                Text("pulling the last 28 days…")
                    .font(Font.Soma.margin)
                    .foregroundStyle(Color.inkSoft)
            }
        case .done(let days):
            Text("connected — \(days) days of signal ready.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.persimmon)
        case .failed(let msg):
            Text(msg)
                .font(Font.Soma.margin)
                .foregroundStyle(Color.persimmon)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionRow: some View {
        HStack {
            Button("close") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)

            Spacer()

            Button {
                Task { await connect() }
            } label: {
                Text("connect")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(!aggregator.isAvailable || state == .requesting)
        }
    }

    private func connect() async {
        state = .requesting
        do {
            let granted = try await aggregator.requestAuthorization()
            guard granted else {
                state = .failed("HealthKit permission couldn't be requested on this device.")
                return
            }
            state = .syncing(count: nil)
            let rows = try await aggregator.aggregate(days: 28)
            try await repo.upsert(rows)
            HealthKitForegroundSync.markConnected()
            state = .done(days: rows.count)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
