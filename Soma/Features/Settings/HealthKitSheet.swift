import SwiftUI

/// Requests HealthKit read authorization, pulls the first rollup, and from
/// then on reports where the sync stands.
///
/// HealthKit won't tell us whether reads were actually granted, so the sheet
/// reflects our own connection flag rather than pretending to know: once the
/// user has connected, it opens showing that, plus when we last managed to
/// sync — not the "not yet connected" line it used to greet everyone with.
struct HealthKitSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let aggregator = HealthKitAggregator.shared

    @State private var state: LoadState = .idle

    enum LoadState: Equatable {
        case idle
        case requesting
        case syncing
        /// `days` is known only right after a sync we just ran.
        case connected(lastSync: Date?, days: Int?)
        case disconnected
        case failed(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        var isBusy: Bool { self == .requesting || self == .syncing }
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
        .onAppear(perform: restoreState)
    }

    /// The connection flag outlives the sheet, so read it back every time
    /// rather than starting from `.idle`.
    private func restoreState() {
        guard !state.isBusy else { return }
        if HealthKitSync.isConnected {
            state = .connected(lastSync: HealthKitSync.lastSyncedAt, days: nil)
        } else if state != .disconnected {
            state = .idle
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch state {
        case .idle:
            statusText(aggregator.isAvailable
                       ? "not yet connected — tap “connect” to allow."
                       : "HealthKit isn't available on this device.",
                       color: Color.inkSoft)
        case .requesting:
            busyText("waiting on permission…")
        case .syncing:
            busyText("pulling the last \(HealthKitAggregator.windowDays) days…")
        case .connected(let lastSync, let days):
            VStack(alignment: .leading, spacing: 2) {
                statusText(connectedLine(days: days), color: Color.bay)
                if let lastSync {
                    statusText("last synced \(SomaFormat.relative(lastSync)) · keeps up on its own.",
                               color: Color.inkSoft)
                } else {
                    statusText("keeps up on its own from here.", color: Color.inkSoft)
                }
            }
        case .disconnected:
            VStack(alignment: .leading, spacing: 2) {
                statusText("disconnected — nothing more will sync.", color: Color.inkSoft)
                statusText("days already stored stay until you delete your account.",
                           color: Color.inkSoft)
            }
        case .failed(let msg):
            statusText(msg, color: Color.persimmon)
        }
    }

    private func connectedLine(days: Int?) -> String {
        guard let days else { return "connected." }
        return days == 0
            ? "connected — no signal in HealthKit yet."
            : "connected — \(days) days of signal ready."
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Font.Soma.margin)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func busyText(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            ProgressView().controlSize(.small).tint(Color.inkSoft)
            statusText(text, color: Color.inkSoft)
        }
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.l) {
            Button("close") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)

            Spacer()

            if state.isConnected {
                Button("disconnect") { disconnect() }
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.inkSoft)
                    .buttonStyle(.plain)
                    .disabled(state.isBusy)
            }

            Button {
                Task { await connect() }
            } label: {
                Text(state.isConnected ? "sync now" : "connect")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(Capsule(style: .continuous).fill(Color.ink))
            }
            .buttonStyle(.plain)
            .disabled(!aggregator.isAvailable || state.isBusy)
        }
    }

    /// Connect and re-sync are the same trip — asking again once we're
    /// already authorized is a no-op that HealthKit answers immediately.
    private func connect() async {
        state = .requesting
        do {
            let granted = try await aggregator.requestAuthorization()
            guard granted else {
                state = .failed("HealthKit permission couldn't be requested on this device.")
                return
            }
            state = .syncing
            let rows = try await HealthKitSync.shared.syncNow()
            HealthKitSync.markConnected()
            // Only now can background delivery start — before this, the
            // connected flag was false and registration would no-op.
            HealthKitSync.shared.startObservingIfConnected()
            state = .connected(lastSync: HealthKitSync.lastSyncedAt, days: rows.count)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Stops the sync. Deliberately does *not* delete what's already stored
    /// — silently erasing weeks of body data behind a button labelled
    /// "disconnect" would be a nasty surprise. Delete account does that.
    private func disconnect() {
        HealthKitSync.shared.stopObserving()
        HealthKitSync.clearConnected()
        state = .disconnected
    }
}
