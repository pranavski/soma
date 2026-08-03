import Foundation
import Supabase
import SwiftUI

/// The always-reachable log line pinned to the insights home — one typed
/// sentence, one tap, done. Insert-then-parse is fire-and-forget so the
/// feed never blocks on the Edge Function; Today picks the row up with
/// whatever parse_status it lands on.
///
/// Deliberately independent of TodayViewModel (another workstream owns
/// it) — this talks straight to MealsRepository + parse-meal.
struct QuickLogField: View {
    @StateObject private var vm = QuickLogViewModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
            if let note = vm.note {
                Text(note)
                    .font(Font.Soma.margin)
                    .foregroundStyle(vm.noteIsError ? Color.persimmon : Color.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            HStack(spacing: Theme.Spacing.s) {
                TextField("just ate? tell me", text: $vm.text, axis: .vertical)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.ink)
                    .lineLimit(1...3)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { vm.submit() }

                Button {
                    vm.submit()
                    focused = false
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.paper)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(vm.canSubmit ? Color.ink : Color.inkSoft.opacity(0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!vm.canSubmit)
                .accessibilityLabel("Log this meal")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .fill(Color.paperRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                            .stroke(Color.rule, lineWidth: 0.6)
                    )
            )
            .shadow(color: Color.paperShadow.opacity(0.5), radius: 14, x: 0, y: 8)
        }
        .animation(.easeOut(duration: 0.18), value: vm.note)
        // Clear the tab bar when resting; sit snug above the keyboard
        // when writing (the bar hides behind the keyboard anyway).
        .padding(.bottom, focused ? Theme.Spacing.m : 96)
        .animation(.easeOut(duration: 0.2), value: focused)
    }
}

// MARK: - View model

@MainActor
final class QuickLogViewModel: ObservableObject {
    @Published var text: String = ""
    /// One quiet line above the field — confirmation or soft trouble.
    @Published private(set) var note: String?
    @Published private(set) var noteIsError = false

    private let repository: MealsRepository
    private let client: SupabaseClient
    private var noteClearTask: Task<Void, Never>?

    init(
        repository: MealsRepository = MealsRepository(),
        client: SupabaseClient = .shared
    ) {
        self.repository = repository
        self.client = client
    }

    var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Fire-and-forget: clear the field immediately, do the work behind
    /// the scenes, and only speak up (softly) if something goes wrong.
    func submit() {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        text = ""
        showNote("noted — parsing quietly…", isError: false)

        Task { [weak self] in
            await self?.logMeal(payload)
        }
    }

    private func logMeal(_ payload: String) async {
        let mealId: UUID
        do {
            // Typed text is source=manual, same as the Today capture sheet's
            // typed path; the transcript column carries it either way.
            mealId = try await repository.insertPendingMeal(
                source: .manual,
                voiceTranscript: payload
            )
        } catch {
            showNote("couldn't save that one — try again in a moment?", isError: true)
            return
        }

        struct ParseRequest: Encodable {
            let meal_id: UUID
            let voice_transcript: String
        }
        do {
            try await client.functions.invoke(
                "parse-meal",
                options: FunctionInvokeOptions(
                    body: ParseRequest(meal_id: mealId, voice_transcript: payload)
                )
            )
            showNote("noted — it's on today's page.", isError: false)
        } catch {
            // Same contract as Today: a 422 means the row was flipped to
            // 'failed' server-side and can be corrected there. The meal is
            // saved either way, so keep the note soft.
            showNote("saved, but couldn't read it — it'll wait on today's page.", isError: true)
        }
    }

    private func showNote(_ message: String, isError: Bool) {
        noteClearTask?.cancel()
        note = message
        noteIsError = isError
        noteClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.note = nil
        }
    }
}

#Preview {
    ZStack {
        PaperBackground()
        VStack {
            Spacer()
            QuickLogField()
                .padding(.horizontal, Theme.Spacing.xl)
        }
    }
}
