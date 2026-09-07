import SwiftUI

/// Press-and-hold actions on a logged meal card: fix what Soma read, or
/// take the whole thing off the record.
///
/// Today and History both draw meal cards and both need the same two
/// answers to "that's wrong," so the menu lives here instead of being
/// written twice.
///
/// The menu only *asks* for a delete — the confirmation is presented by
/// the screen (see `mealDeleteConfirmation`), not by the card. A dialog
/// owned by a card inside a `ForEach` never appears: dismissing the
/// context menu tears the row's presentation down in the same frame the
/// dialog tries to come up. The same reason `TodayView` already holds
/// the correction sheet's binding.
struct MealCardActions: ViewModifier {
    let meal: Meal
    /// Omitted where there's nothing to correct — History is a read-only
    /// index today, so it passes nil.
    var onCorrect: ((Meal) -> Void)?
    /// Ask the screen to confirm removing this meal.
    var onDeleteRequest: (Meal) -> Void

    /// Nothing to correct while a row is still parsing — the guess it
    /// would pre-fill doesn't exist yet. Same gate the Today card's
    /// "not quite right?" chip uses.
    private var canCorrect: Bool {
        onCorrect != nil && (meal.parseStatus == .parsed || meal.parseStatus == .failed)
    }

    func body(content: Content) -> some View {
        content.contextMenu {
            if canCorrect {
                Button {
                    onCorrect?(meal)
                } label: {
                    Label("not quite right?", systemImage: "pencil.line")
                }
            }

            Button(role: .destructive) {
                onDeleteRequest(meal)
            } label: {
                Label("take it off the record", systemImage: "trash")
            }
        }
    }
}

extension View {
    /// Attach the meal card's press-and-hold menu. Pass `onCorrect` only
    /// where a correction sheet is actually wired up.
    func mealCardActions(
        for meal: Meal,
        onCorrect: ((Meal) -> Void)? = nil,
        onDeleteRequest: @escaping (Meal) -> Void
    ) -> some View {
        modifier(
            MealCardActions(meal: meal, onCorrect: onCorrect, onDeleteRequest: onDeleteRequest)
        )
    }

    /// The screen-level half: confirm before anything is removed. A meal
    /// is something the person said happened — the app shouldn't be able
    /// to quietly forget it on a mis-press, and there's no undo behind it.
    ///
    /// Apply this to the screen's root, with `pending` bound to the meal
    /// the card menu asked about.
    func mealDeleteConfirmation(
        for pending: Binding<Meal?>,
        onConfirm: @escaping (Meal) -> Void
    ) -> some View {
        confirmationDialog(
            pending.wrappedValue.map { "take \($0.displayName.lowercased()) off the record?" }
                ?? "take this off the record?",
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { meal in
            Button("take it off", role: .destructive) { onConfirm(meal) }
            Button("keep it", role: .cancel) { pending.wrappedValue = nil }
        } message: { _ in
            Text("it stops counting toward what soma notices. there's no undo.")
        }
    }
}

/// The margin note that makes the menu findable — a long-press is
/// invisible otherwise. Set in the handwritten voice because that's what
/// margin asides are for.
struct MealCardHint: View {
    /// False where the menu only offers removal (History), so the note
    /// doesn't promise an edit the screen can't do.
    var canCorrect: Bool = true

    var body: some View {
        Text(canCorrect
             ? "press and hold a card to fix it or take it off."
             : "press and hold a card to take it off the record.")
            .font(Font.Soma.margin)
            .foregroundStyle(Color.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
