import SwiftUI

/// "Not quite right?" — the per-meal correction sheet, opened from the
/// meal-detail long-press affordance on a RecipeCard.
///
/// It opens on any row that isn't mid-parse: Claude's guess, a failed
/// parse (blank fields), a meal filed with consent off (the person's
/// words as the dish, no range yet), and a meal already corrected once.
///
/// Behavioral rules:
///   * Calorie range is edited as low + high, both required, high >= low.
///     We enforce the spec's "always a range" contract here rather than
///     letting the user enter a single midpoint.
///   * Cuisine picker matches parse-meal's enum exactly — see Cuisine.
///   * Component (item) list is add/edit/remove, capped at 12 by the
///     server. We cap at 12 client-side too so the UI matches.
///   * Submit is disabled until the form is valid; the server also
///     revalidates.
struct CorrectionSheet: View {
    let meal: Meal
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var dishName: String
    @State private var cuisine: Cuisine
    @State private var caloriesLowText: String
    @State private var caloriesHighText: String
    @State private var items: [MealCorrection.Item]
    @State private var newItemName: String = ""
    @State private var newItemQuantity: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var didLoadItems = false

    private let repository: CorrectionsRepository

    init(meal: Meal, repository: CorrectionsRepository = CorrectionsRepository(), onSaved: @escaping () -> Void) {
        self.meal = meal
        self.repository = repository
        self.onSaved = onSaved
        _dishName = State(initialValue: meal.dishName ?? "")
        _cuisine = State(initialValue: Cuisine(rawValue: meal.cuisine ?? "") ?? .other)
        _caloriesLowText = State(initialValue: meal.caloriesLow.map(String.init) ?? "")
        _caloriesHighText = State(initialValue: meal.caloriesHigh.map(String.init) ?? "")
        _items = State(initialValue: [])
    }

    var body: some View {
        ZStack {
            PaperBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    Section(title: "the dish") {
                        TextField("what was it, really?", text: $dishName)
                            .textFieldStyle(.plain)
                            .font(Font.Soma.dish)
                            .foregroundStyle(Color.ink)
                            .padding(.vertical, 8)
                            .padding(.horizontal, Theme.Spacing.m)
                            .background(fieldBackground)
                    }

                    Section(title: "cuisine") {
                        cuisinePicker
                    }

                    Section(title: "calories — a range, never a target") {
                        HStack(spacing: Theme.Spacing.m) {
                            rangeField("low", text: $caloriesLowText)
                            Text("–")
                                .font(Font.Soma.dish)
                                .foregroundStyle(Color.inkSoft)
                            rangeField("high", text: $caloriesHighText)
                            Text("kcal")
                                .font(Font.Soma.caloric)
                                .foregroundStyle(Color.inkSoft)
                        }
                    }

                    Section(title: "what was in it") {
                        itemsList
                    }

                    if let errorText {
                        Text(errorText)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                    } else if !canSubmit {
                        // The sheet also opens on meals that failed to parse,
                        // where the dish and both numbers are blank. Say why
                        // "save" is greyed out instead of leaving the user
                        // poking at a dead button.
                        Text("needs a dish name and both ends of the range.")
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.inkSoft)
                    }

                    actionRow
                }
                .padding(Theme.Spacing.xl)
            }
            // The calorie fields use a number pad, which has no return key —
            // without this there's no way to put the keyboard away.
            .scrollDismissesKeyboard(.interactively)
        }
        // Start from the components parse-meal already found, so "save" keeps
        // them instead of quietly filing a correction that says the meal had
        // nothing in it.
        .task {
            guard !didLoadItems else { return }
            didLoadItems = true
            items = await repository.fetchItems(mealId: meal.id)
        }
    }

    // MARK: - Sub-sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOT QUITE RIGHT")
                    .font(Font.Soma.sectionTag)
                    .tracking(3)
                    .foregroundStyle(Color.persimmon)
                Text("tell it what it should have said.")
                    .font(Font.Soma.pullQuote)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Button("close") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)
        }
    }

    private var cuisinePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(Cuisine.allCases) { c in
                    Button {
                        cuisine = c
                    } label: {
                        Text(c.label)
                            .font(Font.Soma.dishSmall)
                            .foregroundStyle(cuisine == c ? Color.paper : Color.ink)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(cuisine == c ? Color.ink : Color.paperRaised)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.rule, lineWidth: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                    Text("·")
                        .foregroundStyle(Color.inkSoft)
                    Text(item.name)
                        .font(Font.Soma.dishSmall)
                        .foregroundStyle(Color.ink)
                    if let q = item.quantity, !q.isEmpty {
                        Text(q)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.inkSoft)
                    }
                    Spacer()
                    Button {
                        items.removeAll { $0.id == item.id }
                    } label: {
                        Text("remove")
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                InkRule(style: .dotted, color: Color.rule.opacity(0.6), weight: 0.8)
                    .frame(height: 4)
            }

            if items.count < 12 {
                HStack(spacing: Theme.Spacing.s) {
                    TextField("component (e.g. dal)", text: $newItemName)
                        .font(Font.Soma.dishNote)
                        .padding(.vertical, 6)
                        .padding(.horizontal, Theme.Spacing.m)
                        .background(fieldBackground)

                    TextField("qty", text: $newItemQuantity)
                        .font(Font.Soma.dishNote)
                        .frame(width: 68)
                        .padding(.vertical, 6)
                        .padding(.horizontal, Theme.Spacing.m)
                        .background(fieldBackground)

                    Button {
                        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        let qty = newItemQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
                        items.append(MealCorrection.Item(name: name, quantity: qty.isEmpty ? nil : qty))
                        newItemName = ""
                        newItemQuantity = ""
                    } label: {
                        Text("add")
                            .font(Font.Soma.buttonLg)
                            .foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.m) {
            Spacer()
            Button {
                Task { await save() }
            } label: {
                Text(isSubmitting ? "sending…" : "save correction")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canSubmit ? Color.ink : Color.inkSoft.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)
        }
    }

    // MARK: - Helpers

    private func rangeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .font(Font.Soma.numeric)
            .foregroundStyle(Color.ink)
            .frame(width: 72)
            .padding(.vertical, 8)
            .padding(.horizontal, Theme.Spacing.m)
            .background(fieldBackground)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
            .strokeBorder(Color.rule, lineWidth: 0.6)
    }

    private var canSubmit: Bool {
        guard !dishName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let lo = Int(caloriesLowText), let hi = Int(caloriesHighText) else { return false }
        return lo > 0 && hi >= lo
    }

    private func save() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorText = nil

        let corrected = MealCorrection(
            dish_name: dishName.trimmingCharacters(in: .whitespacesAndNewlines),
            cuisine: cuisine.rawValue,
            calories_low: Int(caloriesLowText) ?? 0,
            calories_high: Int(caloriesHighText) ?? 0,
            items: items
        )
        // Only a dish Claude named is an "original guess" worth learning
        // an alias from. A manual row's name is the person's own — a
        // correction of it, or a meal filed with consent off — and teaching
        // the community table "their words → their words" would just be
        // noise in every future parse prompt.
        let original: MealCorrectionOriginal? = meal.dishWasParsed
            ? MealCorrectionOriginal(dish_name: meal.dishName, cuisine: meal.cuisine)
            : nil

        do {
            try await repository.submit(
                mealId: meal.id,
                originalGuess: original,
                corrected: corrected
            )
            onSaved()
            dismiss()
        } catch {
            errorText = "couldn't send — try again?"
        }
    }
}

// MARK: - Section

/// Lightweight section wrapper — an eyebrow tag and its content. Matches
/// the AboutSheet section style so the two sheets read as siblings.
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.persimmon)
            content()
        }
    }
}
