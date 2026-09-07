import Foundation
import OSLog

/// Home-feed view model. The insights feed is the app's front door now:
/// ranked findings, a pull-to-refresh that asks the engine to think, and
/// honest quiet states everywhere else.
@MainActor
final class InsightsViewModel: ObservableObject {
    /// Ranked feed — confidence high→low, then newest first within a level.
    @Published private(set) var insights: [Insight] = []
    /// Plain descriptions of the log, for the stretch before the statistics
    /// can say anything. Server-ordered; see `showsReflections` for when
    /// they earn their place on screen.
    @Published private(set) var reflections: [Reflection] = []
    @Published private(set) var isLoading = false
    /// True while the engine is chewing on requestGeneration(). Drives the
    /// "thinking about your last few weeks…" row.
    @Published private(set) var isGenerating = false
    @Published private(set) var errorText: String?

    private let repository: InsightsRepository
    private let reflectionsRepository: ReflectionsRepository

    init(
        repository: InsightsRepository = InsightsRepository(),
        reflectionsRepository: ReflectionsRepository = ReflectionsRepository()
    ) {
        self.repository = repository
        self.reflectionsRepository = reflectionsRepository
        #if DEBUG
        if Self.isPreview {
            // SOMA_PREVIEW_EMPTY holds the feed empty so headless runs can
            // screenshot the first-week state — the one that only exists
            // before any finding has cleared the correction, and so the one
            // hardest to reach with real data.
            if ProcessInfo.processInfo.environment["SOMA_PREVIEW_EMPTY"] != "1" {
                insights = Self.ranked(InsightSampleData.feed)
            }
            reflections = InsightSampleData.reflections
        }
        #endif
    }

    /// Reflections are the early-days answer, not a permanent second feed.
    /// Once a real finding exists, a list of "you logged 3 meals a day"
    /// beneath it is clutter competing with the thing the app is actually
    /// for — so they yield. The server keeps them current either way, which
    /// is what makes them reappear correctly if the feed is ever empty
    /// again.
    var showsReflections: Bool {
        insights.isEmpty && !reflections.isEmpty
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
            // Two independent reads of the caller's own rows; a reflection
            // failure must not cost the feed its insights, so they are
            // awaited separately rather than in a throwing group.
            insights = Self.ranked(try await repository.fetchRecent(limit: 20))
        } catch {
            Self.log.error("insights fetch failed: \(String(describing: error), privacy: .public)")
            errorText = Self.loadFailureText(for: error)
            #if DEBUG
            // On a phone there is no console to read from the build machine,
            // so a debug build says the quiet part out loud. Release builds
            // keep the one calm sentence.
            errorText = (errorText ?? "") + "\n\(error)"
            #endif
        }
        do {
            reflections = try await reflectionsRepository.fetchCurrent()
        } catch {
            // Reflections are the early-days garnish; losing them is not
            // worth a message. Logged, though — silence in the UI should
            // not mean silence in the logs.
            Self.log.error("reflections fetch failed: \(String(describing: error), privacy: .public)")
        }
        isLoading = false
    }

    /// Pull-to-refresh: ask the engine to think, then re-read the feed.
    /// A generation failure is soft — whatever is already surfaced stays.
    func refresh() async {
        guard !Self.isPreview else { return }
        errorText = nil
        isGenerating = true
        var generationError: Error?
        do {
            try await repository.requestGeneration()
        } catch {
            Self.log.error("insight generation failed: \(String(describing: error), privacy: .public)")
            generationError = error
        }
        await load()
        isGenerating = false
        if let generationError, errorText == nil {
            errorText = "couldn't think it over just now — your notes are safe."
            #if DEBUG
            errorText = (errorText ?? "") + "\n\(generationError)"
            #endif
        }
    }

    /// Two shapes of failure, two sentences. A dropped connection is the
    /// phone's; anything else — an expired session, a decode that no longer
    /// matches the table, a 500 — is ours, and saying "couldn't reach" for
    /// those sends whoever is debugging it to look at the wrong thing.
    static func loadFailureText(for error: Error) -> String {
        // The SDK sometimes hands back its own error with the URL failure
        // tucked underneath, so check both levels before blaming the network.
        let ns = error as NSError
        let offline = ns.domain == NSURLErrorDomain
            || ns.underlyingErrors.contains { ($0 as NSError).domain == NSURLErrorDomain }
        return offline
            ? "couldn't reach your notes — pull to try again."
            : "your notes didn't come back just now — pull to try again."
    }

    private static let log = Logger(subsystem: "com.pranavsurampudi.soma", category: "insights")

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
            windowDays: 28,
            mechanism: nil,
            evidenceCitation: nil,
            evidenceGrade: nil
        ),
        Insight(
            id: UUID(),
            createdAt: day(-3),
            claim: "Higher-step days tend to be followed by slightly longer sleep that night.",
            evidence: "15 paired days; the association held on most, not all, of them.",
            confidence: .medium,
            suggestedAction: "worth watching on days you're out and about more than usual.",
            windowDays: 28,
            mechanism: nil,
            evidenceCitation: nil,
            evidenceGrade: nil
        ),
        Insight(
            id: UUID(),
            createdAt: day(-6),
            claim: "Days after the lentil soup read a touch higher on energy — loosely, so far.",
            evidence: "eaten 4 times; next days averaged 3.6 against your 3.1 baseline.",
            confidence: .low,
            suggestedAction: nil,
            windowDays: 28,
            mechanism: nil,
            evidenceCitation: nil,
            evidenceGrade: nil
        ),
        Insight(
            id: UUID(),
            createdAt: day(-9),
            claim: "Late plates and overnight resting heart rate may drift together — too few nights to say.",
            evidence: "6 late nights ran about 2 bpm above earlier ones; under our usual bar.",
            confidence: .low,
            suggestedAction: "no need to change anything — another week or two will make this clearer.",
            windowDays: 28,
            mechanism: nil,
            evidenceCitation: nil,
            evidenceGrade: nil
        ),
        // The one sample that carries published context, so the preview
        // exercises both card shapes. Note the division of voice: the claim
        // is hedged and about these 30 days, the mechanism is declarative and
        // about people in general.
        Insight(
            id: UUID(),
            createdAt: day(0),
            claim: "Nights after an afternoon coffee tend to run shorter on sleep — about 6h10m across those 12 days against 7h20m on the 14 without.",
            evidence: "12 days with caffeine after 2pm averaged 6h10m of sleep; the 14 without averaged 7h20m.",
            confidence: .high,
            suggestedAction: "worth watching whether an earlier last coffee shifts this.",
            windowDays: 28,
            mechanism: "Caffeine blocks adenosine receptors, and the resulting alertness can persist for many hours; in controlled trials, caffeine taken closer to bedtime shortens total sleep time and lengthens the time it takes to fall asleep.",
            evidenceCitation: "The effect of caffeine on subsequent sleep: A systematic review and meta-analysis. Sleep Medicine Reviews 69:101764, 2023. Dose and timing effects of caffeine on subsequent sleep: a randomized clinical crossover trial. Sleep 48(4):zsae230, 2025.",
            evidenceGrade: "A"
        )
    ]

    /// The early-days set, as the Edge Function would render it on about
    /// day five. Descriptive only — nothing here relates a meal to a body
    /// signal, which is the property that makes them safe this early.
    static let reflections: [Reflection] = [
        Reflection(
            kind: "repeat_dish",
            body: "greek yogurt + berries is what you've come back to most.",
            detail: "on 4 of your 5 logged days; chana masala on 3.",
            sortOrder: 0,
            windowDays: 30
        ),
        Reflection(
            kind: "meal_timing",
            body: "Your last meal has landed between 19:00 and 21:00.",
            detail: "across 5 days; first plate to last runs about 12 hours.",
            sortOrder: 1,
            windowDays: 30
        ),
        Reflection(
            kind: "calorie_range",
            body: "Your fully-logged days have totalled somewhere around ~1,650–2,300.",
            detail: "4 of your 5 days had every meal parsed — the rest aren't counted here.",
            sortOrder: 2,
            windowDays: 30
        )
    ]

    private static func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }
}
#endif
