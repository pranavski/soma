import Foundation
import Supabase
import UIKit

@MainActor
final class TodayViewModel: ObservableObject {
    @Published private(set) var meals: [Meal] = []
    @Published private(set) var recentDishes: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    /// True when there's no daily_checkin for today yet — surfaces the
    /// "quiet check" nudge on Today.
    @Published private(set) var needsCheckin: Bool = false

    private let repository: MealsRepository
    private let checkins: DailyCheckinsRepository
    private let client: SupabaseClient

    init(
        repository: MealsRepository = MealsRepository(),
        checkins: DailyCheckinsRepository = DailyCheckinsRepository(),
        client: SupabaseClient = .shared
    ) {
        self.repository = repository
        self.checkins = checkins
        self.client = client
        #if DEBUG
        if ProcessInfo.processInfo.environment["SOMA_PREVIEW"] == "1" {
            self.meals = SampleData.logged
        }
        #endif
    }

    func load() async {
        // Only show the loading flash on a cold load; refreshes happen quietly.
        if meals.isEmpty {
            isLoading = true
        }
        errorText = nil
        do {
            meals = try await repository.fetchToday()
        } catch {
            errorText = error.localizedDescription
        }
        // Recent dishes and check-in status are best-effort — a failure here
        // shouldn't blank the Today screen.
        recentDishes = (try? await repository.fetchRecentDishNames(limit: 5)) ?? []
        do {
            let existing = try await checkins.fetch(on: Date())
            needsCheckin = existing == nil
        } catch {
            // Any error (network, missing table on first-ever launch) — hide
            // the nudge rather than nag.
            needsCheckin = false
        }
        isLoading = false
    }

    /// One-tap repeat of a prior dish. Inserts a `source='repeat'` row
    /// carrying the previous parse; no Edge Function round-trip.
    func repeatDish(_ dish: String) async {
        errorText = nil
        do {
            _ = try await repository.repeatMeal(dishName: dish)
        } catch {
            errorText = error.localizedDescription
        }
        await load()
    }

    /// Insert a pending meal, kick off the Edge Function, then refresh so the
    /// row reappears with whatever parse_status the function landed on.
    /// The card renders "parsing…" while we wait — see `Meal.displayName`.
    func submit(transcript: String, source: Meal.Source = .voice) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        errorText = nil

        let mealId: UUID
        do {
            mealId = try await repository.insertPendingMeal(
                source: source,
                voiceTranscript: trimmed
            )
        } catch {
            errorText = error.localizedDescription
            return
        }

        await load()

        struct ParseRequest: Encodable {
            let meal_id: UUID
            let voice_transcript: String
        }
        do {
            try await client.functions.invoke(
                "parse-meal",
                options: FunctionInvokeOptions(
                    body: ParseRequest(meal_id: mealId, voice_transcript: trimmed)
                )
            )
        } catch {
            // 422 from the function is the documented Claude-failure path —
            // it still updates the row to parse_status='failed', so reload
            // and surface a soft note rather than a hard error.
            errorText = "couldn't read that one — try again?"
        }

        await load()
    }

    /// Photo logging. Upload happens BEFORE the row insert — the storage
    /// path embeds the meal id, and inserting first would leave a forever-
    /// "parsing…" row if the upload then failed. An orphaned photo from a
    /// failed insert is the cheaper kind of debris.
    func submitPhoto(_ image: UIImage) async {
        errorText = nil
        guard let data = MealPhoto.uploadData(from: image) else {
            errorText = "couldn't read that photo — try again?"
            return
        }

        let mealId = UUID()
        let photoPath: String
        do {
            photoPath = try await repository.uploadMealPhoto(data, mealId: mealId)
            try await repository.insertPendingMeal(
                source: .photo,
                voiceTranscript: nil,
                photoPath: photoPath,
                id: mealId
            )
        } catch {
            errorText = error.localizedDescription
            return
        }

        await load()

        struct ParseRequest: Encodable {
            let meal_id: UUID
            let photo_path: String
        }
        do {
            try await client.functions.invoke(
                "parse-meal",
                options: FunctionInvokeOptions(
                    body: ParseRequest(meal_id: mealId, photo_path: photoPath)
                )
            )
        } catch {
            // Same contract as the voice path: 422 means the function
            // already flipped the row to 'failed' — the card offers the
            // manual correction path, so keep the note soft.
            errorText = "couldn't read that one — try again?"
        }

        await load()
    }
}
