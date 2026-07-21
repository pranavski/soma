import SwiftUI

/// Settings → "send feedback". Free-text + category picker.
///
/// We deliberately keep this small — no title field, no attachments, no
/// email. If someone wants to say "the AI called my chana masala 'stew'",
/// they can type it in one field and we route by category server-side.
struct FeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackCategory = .other
    /// Body of the feedback note. Named `noteBody` to avoid colliding
    /// with SwiftUI's required `body` property on View.
    @State private var noteBody: String = ""
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var didSubmit = false

    private let repository: FeedbackRepository

    init(repository: FeedbackRepository = FeedbackRepository()) {
        self.repository = repository
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    if didSubmit {
                        thanks
                    } else {
                        categoryPicker
                        bodyField
                        if let errorText {
                            Text(errorText)
                                .font(Font.Soma.margin)
                                .foregroundStyle(Color.persimmon)
                        }
                        actionRow
                    }

                    footnote
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SEND FEEDBACK")
                    .font(Font.Soma.sectionTag)
                    .tracking(3)
                    .foregroundStyle(Color.persimmon)
                Text("what could be better?")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Button("close") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("kind")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.persimmon)

            HStack(spacing: Theme.Spacing.s) {
                ForEach(FeedbackCategory.allCases) { c in
                    Button {
                        category = c
                    } label: {
                        Text(c.label)
                            .font(Font.Soma.dishSmall)
                            .foregroundStyle(category == c ? Color.paper : Color.ink)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(category == c ? Color.ink : Color.paperRaised)
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

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("in your words")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.persimmon)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                    .strokeBorder(Color.rule, lineWidth: 0.6)
                TextField("what went well, what didn't…", text: $noteBody, axis: .vertical)
                    .font(Font.Soma.dishNote)
                    .foregroundStyle(Color.ink)
                    .lineLimit(5...12)
                    .padding(Theme.Spacing.l)
            }
            .frame(minHeight: 160)
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            Button {
                Task { await send() }
            } label: {
                Text(isSubmitting ? "sending…" : "send")
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

    private var thanks: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("thanks — it landed.")
                .font(Font.Soma.pullQuote)
                .foregroundStyle(Color.ink)
            Text("we read every one, quietly.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            InkRule(style: .wavy, color: Color.rule, weight: 1.0)
                .frame(width: 100)
            Text("your note is stored privately in your account — visible to you and to the soma team, no one else.")
                .font(Font.Soma.margin)
                .foregroundStyle(Color.inkSoft)
                .lineSpacing(3)
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var canSubmit: Bool {
        !noteBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorText = nil
        defer { isSubmitting = false }
        do {
            try await repository.submit(category: category, body: noteBody)
            didSubmit = true
        } catch {
            errorText = "couldn't send — try again?"
        }
    }
}

#Preview {
    FeedbackSheet()
}
