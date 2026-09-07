import Foundation
import Supabase

/// The one path a meal takes onto the record: insert the row, then hand it
/// to `parse-meal`.
///
/// Today logs against now and History logs against a day you pick, but the
/// steps in between are identical — the row has to exist before the parse
/// so a "parsing…" card can render, the Claude call is gated on consent,
/// and a parse failure is a soft note rather than a lost meal. That
/// sequence lived inside `TodayViewModel`; it lives here so backdating a
/// meal from History can't quietly drift from logging one on Today.
@MainActor
struct MealLogger {
    /// What the caller has to know afterwards. `note` is soft — the meal is
    /// saved either way — and `parseAttempted` says whether a second read of
    /// the row is worth it, since only a parse can have changed it.
    struct Receipt {
        let mealId: UUID
        let note: String?
        let parseAttempted: Bool
    }

    private let repository: MealsRepository
    private let client: SupabaseClient
    private let disclosure: AIDisclosure

    init(
        repository: MealsRepository = MealsRepository(),
        client: SupabaseClient = .shared,
        // Resolved in the body rather than as a default argument, which is
        // evaluated at the (non-isolated) call site — AIDisclosure is
        // @MainActor.
        disclosure: AIDisclosure? = nil
    ) {
        self.repository = repository
        self.client = client
        self.disclosure = disclosure ?? .shared
    }

    /// Spoken or typed meal. `onInserted` runs once the row exists and
    /// before the parse round-trip, so the screen can put a "parsing…" card
    /// up instead of holding a spinner over the whole flow.
    func log(
        transcript: String,
        source: Meal.Source,
        eatenAt: Date,
        onInserted: () async -> Void
    ) async throws -> Receipt {
        let mealId = try await repository.insertPendingMeal(
            source: source,
            voiceTranscript: transcript,
            eatenAt: eatenAt
        )

        await onInserted()

        // Guideline 5.1.2(i): no personal data reaches Anthropic without
        // explicit consent. The meal is already saved — it simply stays
        // unparsed, and the card's "not quite right?" sheet fills it in.
        guard disclosure.hasConsented else {
            return Receipt(
                mealId: mealId,
                note: "saved. soma won't send it to Claude to be read until you say it's ok — see the kitchen.",
                parseAttempted: false
            )
        }

        struct ParseRequest: Encodable {
            let meal_id: UUID
            let voice_transcript: String
        }

        return await invokeParse(
            mealId: mealId,
            body: ParseRequest(meal_id: mealId, voice_transcript: transcript)
        )
    }

    /// One-tap repeat of a prior dish, on whichever day the caller names.
    /// No Edge Function round-trip — the parse came with the original.
    @discardableResult
    func repeatDish(_ dish: String, eatenAt: Date) async throws -> UUID {
        try await repository.repeatMeal(dishName: dish, eatenAt: eatenAt)
    }

    /// A 422 from the function is the documented Claude-failure path — it
    /// still updates the row to parse_status='failed', so the caller reloads
    /// and shows a soft note rather than a hard error.
    private func invokeParse(mealId: UUID, body: some Encodable) async -> Receipt {
        do {
            try await client.functions.invoke(
                "parse-meal",
                options: FunctionInvokeOptions(body: body)
            )
            return Receipt(mealId: mealId, note: nil, parseAttempted: true)
        } catch {
            return Receipt(
                mealId: mealId,
                note: "couldn't read that one — try again?",
                parseAttempted: true
            )
        }
    }
}
