import Foundation
import HealthKit

/// Reads raw HealthKit samples on-device, computes one aggregate per local
/// day, and hands them back so `HealthDaysRepository` can upsert the rollup.
///
/// **Raw HealthKit reads never leave the device.** Only the per-day
/// `HealthDay` values (steps, sleep_minutes, resting_hr_bpm, hrv_ms,
/// weight_kg, active_energy_kcal, workout_minutes) sync.
@MainActor
final class HealthKitAggregator {
    static let shared = HealthKitAggregator()

    /// `nil` only where the device genuinely has no health database. The
    /// iOS Simulator *does* report HealthKit as available (the store is
    /// simply empty until you add samples in the Health app), so this flow
    /// is exercisable there — an empty sync is a legitimate outcome, not a
    /// broken one.
    private let store: HKHealthStore?

    private init() {
        self.store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    var isAvailable: Bool { store != nil }

    /// Escape hatch for the sync coordinator, which needs the same store to
    /// register observer queries and toggle background delivery.
    var healthStore: HKHealthStore? { store }

    // MARK: - Types we read
    // Sleep is HKCategoryTypeIdentifier; the others are HKQuantityTypeIdentifier.

    /// The sample types themselves — observer queries need `HKSampleType`,
    /// which is narrower than the `HKObjectType` authorization takes.
    static var sampleTypes: [HKSampleType] {
        var types: [HKSampleType] = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.append(steps) }
        if let rhr   = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.append(rhr) }
        if let hrv   = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.append(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }
        if let mass  = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.append(mass) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.append(energy) }
        types.append(HKObjectType.workoutType())
        return types
    }

    private var readTypes: Set<HKObjectType> {
        Set(Self.sampleTypes.map { $0 as HKObjectType })
    }

    // MARK: - Authorization

    /// Prompts once for read access to steps + sleep + RHR + HRV. The user
    /// can deny individual types; the aggregator simply reports nil for
    /// anything unavailable and the tier decays gracefully.
    ///
    /// Returns whether we now have permission to *ask questions* — HealthKit
    /// deliberately hides denial vs. "not yet asked" from us, so the value
    /// is: "did the sheet get through without an error."
    func requestAuthorization() async throws -> Bool {
        guard let store else { return false }
        try await store.requestAuthorization(toShare: [], read: readTypes)
        return true
    }

    // MARK: - Aggregation

    /// The trailing window we sync. Matches `WINDOW_DAYS` in
    /// `supabase/functions/generate-insights/index.ts` — syncing a shorter
    /// window than the engine scores leaves the oldest days of every fresh
    /// connection empty.
    nonisolated static let windowDays = 30

    /// Compute per-day rollups for the last `days` local days ending today.
    /// Returns an entry for every day HealthKit has *any* signal for; days
    /// with zero data are skipped so we don't paper over gaps with fake zeros.
    func aggregate(days: Int = windowDays, calendar: Calendar = .current) async throws -> [HealthDay] {
        guard let store else { return [] }
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }

        async let steps = sumQuantityByDay(store: store, identifier: .stepCount,
                                           unit: .count(),
                                           start: start, end: anchor, calendar: calendar)
        async let rhr   = averageQuantityByDay(store: store, identifier: .restingHeartRate,
                                               unit: HKUnit.count().unitDivided(by: .minute()),
                                               start: start, end: anchor, calendar: calendar)
        async let hrv   = averageQuantityByDay(store: store, identifier: .heartRateVariabilitySDNN,
                                               unit: HKUnit.secondUnit(with: .milli),
                                               start: start, end: anchor, calendar: calendar)
        async let sleep = sleepMinutesByStartDay(store: store, start: start, end: anchor, calendar: calendar)
        async let weight = averageQuantityByDay(store: store, identifier: .bodyMass,
                                                unit: .gramUnit(with: .kilo),
                                                start: start, end: anchor, calendar: calendar)
        async let energy = sumQuantityByDay(store: store, identifier: .activeEnergyBurned,
                                            unit: .kilocalorie(),
                                            start: start, end: anchor, calendar: calendar)
        async let workouts = workoutMinutesByStartDay(store: store, start: start, end: anchor, calendar: calendar)

        return HealthDayBucketing.rows(
            from: start,
            through: anchor,
            calendar: calendar,
            steps: try await steps,
            sleepMinutes: try await sleep,
            restingHr: try await rhr,
            hrv: try await hrv,
            weightKg: try await weight,
            activeEnergy: try await energy,
            workoutMinutes: try await workouts
        )
    }

    // MARK: - Query helpers

    private func sumQuantityByDay(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [Date: Int] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        let interval = DateComponents(day: 1)
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end, options: .strictStartDate)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: anchor,
            intervalComponents: interval
        )
        let collection = try await query.result(for: store)
        var out: [Date: Int] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let sum = stats.sumQuantity() {
                let day = calendar.startOfDay(for: stats.startDate)
                out[day] = Int(sum.doubleValue(for: unit))
            }
        }
        return out
    }

    private func averageQuantityByDay(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [Date: Double] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [:] }
        let interval = DateComponents(day: 1)
        let anchor = calendar.startOfDay(for: start)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: calendar.date(byAdding: .day, value: 1, to: end) ?? end, options: .strictStartDate)
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .discreteAverage,
            anchorDate: anchor,
            intervalComponents: interval
        )
        let collection = try await query.result(for: store)
        var out: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let avg = stats.averageQuantity() {
                let day = calendar.startOfDay(for: stats.startDate)
                out[day] = avg.doubleValue(for: unit)
            }
        }
        return out
    }

    /// Sleep is attributed to the day the *primary* asleep session started,
    /// per spec: `sleep_minutes` on day d = the night that starts on d.
    private func sleepMinutesByStartDay(
        store: HKHealthStore,
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [Date: Int] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let predicate = HKQuery.predicateForSamples(
            withStart: calendar.date(byAdding: .day, value: -1, to: start) ?? start,
            end: calendar.date(byAdding: .day, value: 1, to: end) ?? end,
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)

        // Only "asleep" values count — HKCategoryValueSleepAnalysis has
        // multiple asleep sub-stages plus inBed / awake. We want any
        // asleep* value; ignore the rest.
        let sessions = samples
            .filter(Self.isAsleep(sample:))
            .map { HealthDayBucketing.Session(start: $0.startDate, end: $0.endDate) }

        return HealthDayBucketing.minutesByStartDay(sessions, calendar: calendar)
    }

    /// Workouts are attributed to the local day they *started* — a session
    /// that crosses midnight counts entirely toward its start day, matching
    /// how the sleep rollup handles boundary-crossing samples.
    private func workoutMinutesByStartDay(
        store: HKHealthStore,
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [Date: Int] {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: calendar.date(byAdding: .day, value: 1, to: end) ?? end,
            options: .strictStartDate
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let workouts = try await descriptor.result(for: store)

        let sessions = workouts.map {
            HealthDayBucketing.Session(start: $0.startDate, duration: $0.duration)
        }

        return HealthDayBucketing.minutesByStartDay(sessions, calendar: calendar)
    }

    private static func isAsleep(sample: HKCategorySample) -> Bool {
        // On iOS 16+ Apple broke sleep into sub-stages; anything that
        // represents "actually asleep" counts. `.inBed` and `.awake` don't.
        switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }
}

/// Keeps `health_days` fresh without the user thinking about it.
///
/// Two paths feed it:
/// - **Background delivery.** `HKObserverQuery` + `enableBackgroundDelivery`
///   wake the app when new samples land, so the nightly insight job doesn't
///   score a window that stopped updating whenever the user last opened us.
/// - **App foreground.** A belt-and-braces pass, in case background wakeups
///   were throttled or the user denied nothing but never opens the app.
///
/// HealthKit deliberately hides read-authorization state, so "connected" is
/// our own flag, set the first time the Settings sheet syncs.
@MainActor
final class HealthKitSync {
    static let shared = HealthKitSync()

    private static let connectedKey = "soma.healthkit.connected"
    private static let lastSyncKey  = "soma.healthkit.lastSyncAt"

    /// Foreground passes are cheap but pointless in bursts. Background
    /// wakeups get a shorter floor: they're the path that has to keep the
    /// nightly job fed, and HealthKit already rate-limits them to hourly.
    private static let foregroundMinInterval: TimeInterval = 6 * 3600
    private static let backgroundMinInterval: TimeInterval = 3 * 3600

    private var isSyncing = false
    private var observers: [HKObserverQuery] = []

    // MARK: - Connection flag

    static var isConnected: Bool {
        UserDefaults.standard.bool(forKey: connectedKey)
    }

    /// When we last successfully upserted a rollup — `nil` if never.
    static var lastSyncedAt: Date? {
        UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    static func markConnected() {
        UserDefaults.standard.set(true, forKey: connectedKey)
    }

    /// Called on sign-out and account deletion. The flag lives in
    /// UserDefaults, which is per-device rather than per-account, so without
    /// this the next person to sign in on the phone would silently start
    /// syncing HealthKit aggregates into *their* account on first
    /// foreground — health data crossing accounts with nobody asked.
    static func clearConnected() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: connectedKey)
        defaults.removeObject(forKey: lastSyncKey)
    }

    // MARK: - Background delivery

    /// Register observer queries and ask HealthKit to wake us for new
    /// samples. Safe to call repeatedly — a second call is a no-op while
    /// observers are already running.
    ///
    /// Must run early in launch (see `AppDelegate`): HealthKit can start the
    /// app in the background purely to deliver an update, and the handler
    /// has to already be installed when it does.
    func startObservingIfConnected() {
        guard Self.isConnected, observers.isEmpty,
              let store = HealthKitAggregator.shared.healthStore else { return }

        for type in HealthKitAggregator.sampleTypes {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                // Called off the main actor, and HealthKit keeps retrying
                // with backoff until `completion` runs — so it runs on every
                // path, including the throttled no-op and the failure.
                Task { @MainActor in
                    await self?.sync(minInterval: Self.backgroundMinInterval)
                    completion()
                }
            }
            store.execute(query)
            observers.append(query)

            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in
                // Nothing to do on failure: the foreground pass still covers
                // us, and there's no user-facing promise to walk back.
            }
        }
    }

    /// Tear down observers and background delivery. Called on disconnect and
    /// on sign-out — leaving them running would keep waking the app to sync
    /// data nobody asked us for any more.
    func stopObserving() {
        guard let store = HealthKitAggregator.shared.healthStore else { return }
        for query in observers {
            store.stop(query)
        }
        observers.removeAll()
        store.disableAllBackgroundDelivery { _, _ in }
    }

    // MARK: - Syncing

    func syncIfConnected(repository: HealthDaysRepository = HealthDaysRepository()) async {
        await sync(minInterval: Self.foregroundMinInterval, repository: repository)
    }

    /// Force a pull regardless of the throttle — the Settings sheet's
    /// "connect" and manual re-sync, where the user is watching and expects
    /// something to happen.
    @discardableResult
    func syncNow(repository: HealthDaysRepository = HealthDaysRepository()) async throws -> [HealthDay] {
        let rows = try await HealthKitAggregator.shared.aggregate()
        if !rows.isEmpty {
            try await repository.upsert(rows)
            UserDefaults.standard.set(Date(), forKey: Self.lastSyncKey)
        }
        return rows
    }

    private func sync(
        minInterval: TimeInterval,
        repository: HealthDaysRepository = HealthDaysRepository()
    ) async {
        guard Self.isConnected, !isSyncing else { return }
        if let last = Self.lastSyncedAt, Date().timeIntervalSince(last) < minInterval {
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        // Silent by design — the next pass retries. A background wakeup with
        // no restored auth session lands here too, which is fine.
        _ = try? await syncNow(repository: repository)
    }
}
