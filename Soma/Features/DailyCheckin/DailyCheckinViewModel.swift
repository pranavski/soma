import Foundation

@MainActor
final class DailyCheckinViewModel: ObservableObject {
    /// How far back a missed day can still be filled in. The insight engine
    /// only ever reads the last 30 days, so a check-in older than that can't
    /// change anything it sees — the stepper stops there rather than letting
    /// the user wander backwards through the whole archive.
    static let maxLookbackDays = 30

    /// The local day being checked in for, normalised to start-of-day so the
    /// stepper's comparisons and the `check_date` we write always agree.
    @Published private(set) var day: Date
    @Published var energy: Int = 3
    @Published var mood: String = ""
    @Published private(set) var isSaving = false
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// True when the day on screen already has a row — the button says
    /// "update" rather than "save".
    @Published private(set) var alreadyLogged = false

    private let repository: DailyCheckinsRepository
    private let calendar: Calendar

    init(
        day: Date = Date(),
        repository: DailyCheckinsRepository = DailyCheckinsRepository(),
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.calendar = calendar
        self.day = calendar.startOfDay(for: day)
    }

    // MARK: - The editable window

    /// Can a check-in still be filed for `day`? Never the future — you can't
    /// report on a day that hasn't happened — and never further back than
    /// `maxLookbackDays`.
    static func isEditable(_ day: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: day)
        guard target <= today else { return false }
        guard let floor = calendar.date(byAdding: .day, value: -maxLookbackDays, to: today) else {
            return false
        }
        return target >= floor
    }

    var isToday: Bool { calendar.isDateInToday(day) }

    var canStepBack: Bool {
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return false }
        return Self.isEditable(previous, calendar: calendar)
    }

    var canStepForward: Bool { !isToday }

    /// Move the sheet to another day and load whatever is on file for it.
    /// Ignored while a load is in flight so repeated taps can't interleave
    /// two fetches and land the wrong day's answers on screen.
    func step(by days: Int) async {
        guard !isLoading, !isSaving else { return }
        guard let next = calendar.date(byAdding: .day, value: days, to: day),
              Self.isEditable(next, calendar: calendar) else { return }
        day = calendar.startOfDay(for: next)
        await load()
    }

    // MARK: - Load / save

    /// Preload the day's row if one already exists so the user sees their
    /// previous answer instead of a fresh scale — re-checking a day just
    /// updates the existing row via the (user_id, check_date) unique index.
    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            if let existing = try await repository.fetch(on: day) {
                energy = existing.energy
                mood = existing.mood ?? ""
                alreadyLogged = true
            } else {
                // Stepping onto a blank day has to clear the previous day's
                // answers, otherwise they'd get saved onto this one.
                energy = 3
                mood = ""
                alreadyLogged = false
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Save; returns true on success so the caller can dismiss.
    func save() async -> Bool {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await repository.upsert(energy: energy, mood: mood, on: day)
            alreadyLogged = true
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
