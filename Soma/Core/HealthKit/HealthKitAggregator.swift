import Foundation
import HealthKit

/// Reads raw HealthKit samples on-device, computes one aggregate per local
/// day, and hands them back so `HealthDaysRepository` can upsert the rollup.
///
/// **Raw HealthKit reads never leave the device.** Only the per-day
/// `HealthDay` values (steps, sleep_minutes, resting_hr_bpm, hrv_ms) sync.
@MainActor
final class HealthKitAggregator {
    static let shared = HealthKitAggregator()

    /// `nil` on iOS Simulator (HealthKit is unavailable there in most builds)
    /// or on hardware where the store fails to initialize.
    private let store: HKHealthStore?

    private init() {
        self.store = HKHealthStore.isHealthDataAvailable() ? HKHealthStore() : nil
    }

    var isAvailable: Bool { store != nil }

    // MARK: - Types we read
    // Sleep is HKCategoryTypeIdentifier; the others are HKQuantityTypeIdentifier.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let rhr   = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { types.insert(rhr) }
        if let hrv   = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { types.insert(hrv) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
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

    /// Compute per-day rollups for the last `days` local days ending today.
    /// Returns an entry for every day HealthKit has *any* signal for; days
    /// with zero data are skipped so we don't paper over gaps with fake zeros.
    func aggregate(days: Int = 28, calendar: Calendar = .current) async throws -> [HealthDay] {
        guard let store else { return [] }
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: anchor) else { return [] }

        async let steps = stepsByDay(store: store, start: start, end: anchor, calendar: calendar)
        async let rhr   = averageQuantityByDay(store: store, identifier: .restingHeartRate,
                                               unit: HKUnit.count().unitDivided(by: .minute()),
                                               start: start, end: anchor, calendar: calendar)
        async let hrv   = averageQuantityByDay(store: store, identifier: .heartRateVariabilitySDNN,
                                               unit: HKUnit.secondUnit(with: .milli),
                                               start: start, end: anchor, calendar: calendar)
        async let sleep = sleepMinutesByStartDay(store: store, start: start, end: anchor, calendar: calendar)

        let stepMap  = try await steps
        let rhrMap   = try await rhr
        let hrvMap   = try await hrv
        let sleepMap = try await sleep

        var out: [HealthDay] = []
        var day = start
        while day <= anchor {
            let key = calendar.startOfDay(for: day)
            let s   = stepMap[key]
            let sm  = sleepMap[key]
            let r   = rhrMap[key]
            let h   = hrvMap[key]
            // Skip days with literally nothing — we don't want to overwrite
            // a real earlier row with (nil, nil, nil, nil) and drop its tier.
            if s != nil || sm != nil || r != nil || h != nil {
                out.append(HealthDay(
                    day: key,
                    steps: s,
                    sleepMinutes: sm,
                    restingHrBpm: r,
                    hrvMs: h,
                    tier: HealthDay.tier(steps: s, sleep: sm, rhr: r, hrv: h)
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    // MARK: - Query helpers

    private func stepsByDay(
        store: HKHealthStore,
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [Date: Int] {
        guard let type = HKObjectType.quantityType(forIdentifier: .stepCount) else { return [:] }
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
                out[day] = Int(sum.doubleValue(for: .count()))
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

        var minutesByStartDay: [Date: Int] = [:]
        for s in samples {
            // Only "asleep" values count — HKCategoryValueSleepAnalysis has
            // multiple asleep sub-stages plus inBed / awake. We want any
            // asleep* value; ignore the rest.
            guard Self.isAsleep(sample: s) else { continue }
            let day = calendar.startOfDay(for: s.startDate)
            let minutes = Int(s.endDate.timeIntervalSince(s.startDate) / 60.0)
            if minutes > 0 {
                minutesByStartDay[day, default: 0] += minutes
            }
        }
        return minutesByStartDay
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

/// Quiet re-sync on app foreground so `health_days` doesn't go stale the
/// day after the user connects (the insight tiers starve without it).
/// HealthKit deliberately hides read-authorization state, so "connected"
/// is our own flag, set the first time the Settings sheet syncs.
@MainActor
final class HealthKitForegroundSync {
    static let shared = HealthKitForegroundSync()

    private static let connectedKey = "soma.healthkit.connected"
    private static let lastSyncKey  = "soma.healthkit.lastSyncAt"
    private static let minInterval: TimeInterval = 6 * 3600

    private var isSyncing = false

    static func markConnected() {
        UserDefaults.standard.set(true, forKey: connectedKey)
    }

    func syncIfConnected(repository: HealthDaysRepository = HealthDaysRepository()) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.connectedKey), !isSyncing else { return }
        if let last = defaults.object(forKey: Self.lastSyncKey) as? Date,
           Date().timeIntervalSince(last) < Self.minInterval {
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let rows = try await HealthKitAggregator.shared.aggregate(days: 28)
            guard !rows.isEmpty else { return }
            try await repository.upsert(rows)
            defaults.set(Date(), forKey: Self.lastSyncKey)
        } catch {
            // Silent by design — the next foreground pass retries.
        }
    }
}
