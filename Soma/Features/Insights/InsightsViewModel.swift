import Foundation

/// Home-feed view model. The insights feed is the app's front door now:
/// ranked findings, a pull-to-refresh that asks the engine to think, and
/// honest quiet states everywhere else.
@MainActor
final class InsightsViewModel: ObservableObject {
    /// Ranked feed — confidence high→low, then newest first within a level.
    @Published private(set) var insights: [Insight] = []
    @Published private(set) var isLoading = false
    /// True while the engine is chewing on requestGeneration(). Drives the
    /// "thinking about your last few weeks…" row.
    @Published private(set) var isGenerating = false
    @Published private(set) var errorText: String?

    private let repository: InsightsRepository

    init(repository: InsightsRepository = InsightsRepository()) {
        self.repository = repository
        #if DEBUG
        if Self.isPreview {
            insights = Self.ranked(InsightSampleData.feed)
        }
        #endif
    }

    /// Honest about *why* nothing is here — hedged, never shaming.
    var emptyStateNote: String {
        "a couple more weeks of meals and quiet check-ins give patterns room to show. connecting HealthKit (in kitchen) adds sleep and steps to the picture."
    }

    func load() async {
        guard !Self.isPreview else { return }
        // Loading flash only on a cold load; refreshes happen quietly.
        if insights.isEmpty { isLoading = true }
        errorText = nil
        do {
            insights = Self.ranked(try await repository.fetchRecent(limit: 20))
        } catch {
            errorText = "couldn't reach your notes — pull to try again."
        }
        isLoading = false
    }

    /// Pull-to-refresh: ask the engine to think, then re-read the feed.
    /// A generation failure is soft — whatever is already surfaced stays.
    func refresh() async {
        guard !Self.isPreview else { return }
        errorText = nil
        isGenerating = true
        var generationFailed = false
        do {
            try await repository.requestGeneration()
        } catch {
            generationFailed = true
        }
        await load()
        isGenerating = false
        if generationFailed && errorText == nil {
            errorText = "couldn't think it over just now — your notes are safe."
        }
    }

    /// Feed order: strongest signals first, newest first within a level.
    static func ranked(_ items: [Insight]) -> [Insight] {
        items.sorted {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.createdAt > $1.createdAt
        }
    }

    private static var isPreview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1"
        #else
        false
        #endif
    }
}

#if DEBUG
/// Sample feed for SwiftUI previews and SOMA_PREVIEW simulator runs.
/// Copy obeys the insight contract: one hedged sentence per claim, both
/// sides of the comparison, nothing prescriptive, no bare calorie numbers.
enum InsightSampleData {
    static let feed: [Insight] = [
        Insight(
            id: UUID(),
            createdAt: day(-1),
            claim: "Dinners after 9pm tend to precede lower-energy mornings than earlier evenings do.",
            evidence: "11 late evenings averaged 2.1 of 5 next morning; 13 earlier ones averaged 3.0.",
            confidence: .high,
            suggestedAction: "nothing to fix — maybe just notice how the morning feels after a late plate.",
            windowDays: 28
        ),
        Insight(
            id: UUID(),
            createdAt: day(-3),
            claim: "Higher-step days tend to be followed by slightly longer sleep that night.",
            evidence: "15 paired days; the association held on most, not all, of them.",
            confidence: .medium,
            suggestedAction: "worth watching on days you're out and about more than usual.",
            windowDays: 28
        ),
        Insight(
            id: UUID(),
            createdAt: day(-6),
            claim: "Days after the lentil soup read a touch higher on energy — loosely, so far.",
            evidence: "eaten 4 times; next days averaged 3.6 against your 3.1 baseline.",
            confidence: .low,
            suggestedAction: nil,
            windowDays: 28
        ),
        Insight(
            id: UUID(),
            createdAt: day(-9),
            claim: "Late plates and overnight resting heart rate may drift together — too few nights to say.",
            evidence: "6 late nights ran about 2 bpm above earlier ones; under our usual bar.",
            confidence: .low,
            suggestedAction: "no need to change anything — another week or two will make this clearer.",
            windowDays: 28
        )
    ]

    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}
#endif
