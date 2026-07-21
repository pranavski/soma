import Foundation

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var latest: Insight?
    @Published private(set) var prior: [Insight] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?

    private let repository: InsightsRepository

    init(repository: InsightsRepository = InsightsRepository()) {
        self.repository = repository
    }

    var hasInsight: Bool { latest != nil }

    /// Human copy for the empty state. Honest about *why* nothing is here —
    /// hedged, matches the copy contract's tone.
    var emptyStateNote: String {
        "we need a couple more weeks of meals + check-ins before a pattern is worth surfacing."
    }

    func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let recent = try await repository.fetchRecent(limit: 8)
            latest = recent.first
            prior = Array(recent.dropFirst())
        } catch {
            errorText = error.localizedDescription
            latest = nil
            prior = []
        }
    }
}
