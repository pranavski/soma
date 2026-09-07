import Foundation

/// The day-bucketing rules behind `HealthKitAggregator`, factored out so
/// they can be tested without an `HKHealthStore`.
///
/// These are the parts most likely to be subtly wrong — which day a session
/// that crosses midnight belongs to, and whether a day with nothing in it
/// gets a row at all — and they don't need HealthKit to exercise.
enum HealthDayBucketing {

    /// A duration-bearing sample reduced to what bucketing actually needs:
    /// when it started, and how long it ran.
    struct Session: Equatable {
        let start: Date
        let minutes: Int

        init(start: Date, minutes: Int) {
            self.start = start
            self.minutes = minutes
        }

        /// Sleep samples: HealthKit gives a start and an end, and the whole
        /// span counts.
        init(start: Date, end: Date) {
            self.init(start: start, minutes: Int(end.timeIntervalSince(start) / 60.0))
        }

        /// Workouts: `HKWorkout.duration` excludes paused time, so it's a
        /// truer number than `end - start`.
        init(start: Date, duration: TimeInterval) {
            self.init(start: start, minutes: Int(duration / 60.0))
        }
    }

    /// Sum session minutes onto the local day each session *started*. A
    /// session that crosses midnight counts entirely toward its start day —
    /// this is the spec's rule for sleep (`day d` pairs with the night
    /// d→d+1) and we apply the same one to workouts for consistency.
    ///
    /// Zero- and negative-length sessions are dropped rather than recorded
    /// as a 0, so a day with only junk samples stays absent instead of
    /// claiming "0 minutes of sleep."
    static func minutesByStartDay(_ sessions: [Session], calendar: Calendar) -> [Date: Int] {
        var out: [Date: Int] = [:]
        for session in sessions where session.minutes > 0 {
            let day = calendar.startOfDay(for: session.start)
            out[day, default: 0] += session.minutes
        }
        return out
    }

    /// Assemble one `HealthDay` per local day in `start...end` that has at
    /// least one signal.
    ///
    /// Days with literally nothing are skipped: writing an all-nil row would
    /// overwrite a real earlier sync with blanks and drop that day's tier
    /// back to 0.
    static func rows(
        from start: Date,
        through end: Date,
        calendar: Calendar,
        steps: [Date: Int] = [:],
        sleepMinutes: [Date: Int] = [:],
        restingHr: [Date: Double] = [:],
        hrv: [Date: Double] = [:],
        weightKg: [Date: Double] = [:],
        activeEnergy: [Date: Int] = [:],
        workoutMinutes: [Date: Int] = [:]
    ) -> [HealthDay] {
        var out: [HealthDay] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        while day <= last {
            let s  = steps[day]
            let sm = sleepMinutes[day]
            let r  = restingHr[day]
            let h  = hrv[day]
            let w  = weightKg[day]
            let e  = activeEnergy[day]
            let wm = workoutMinutes[day]

            if s != nil || sm != nil || r != nil || h != nil || w != nil || e != nil || wm != nil {
                out.append(HealthDay(
                    day: day,
                    steps: s,
                    sleepMinutes: sm,
                    restingHrBpm: r,
                    hrvMs: h,
                    weightKg: w,
                    activeEnergyKcal: e,
                    workoutMinutes: wm,
                    tier: HealthDay.tier(steps: s, sleep: sm, rhr: r, hrv: h)
                ))
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }
}
