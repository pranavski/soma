import Foundation

@MainActor
final class DailyCheckinViewModel: ObservableObject {
    @Published var energy: Int = 3
    @Published var mood: String = ""
    @Published private(set) var isSaving = false
    @Published private(set) var errorText: String?
    @Published private(set) var alreadyLoggedToday = false

    private let repository: DailyCheckinsRepository

    init(repository: DailyCheckinsRepository = DailyCheckinsRepository()) {
        self.repository = repository
    }

    /// Preload today's row if one already exists so the user sees their
    /// previous answer instead of a fresh scale — same-day changes just
    /// update the existing row via the (user_id, check_date) unique index.
    func load() async {
        errorText = nil
        do {
            if let existing = try await repository.fetch(on: Date()) {
                energy = existing.energy
                mood = existing.mood ?? ""
                alreadyLoggedToday = true
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
            try await repository.upsertToday(energy: energy, mood: mood)
            alreadyLoggedToday = true
            return true
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }
}
