import SwiftUI

/// Two-tap delete-account confirmation. Apple's guideline 5.1.1(v)
/// requires an in-app deletion path for any app that gates a user account
/// (Sign in with Apple counts). This sheet:
///
///   1. Says explicitly what will disappear.
///   2. Requires the user to type "delete" — much harder to trigger by
///      accident than a checkmark, and reads honest.
///   3. Calls the delete-account Edge Function, which cascades all
///      owned rows AND removes the auth.users row.
///   4. Signs out locally so the JWT + KeychainAuthStorage cache clear.
struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: SessionStore

    @State private var confirmation: String = ""
    @State private var isDeleting = false
    @State private var errorText: String?

    private let repository: AccountRepository
    private let appleSignIn = AppleSignInCoordinator()

    init(repository: AccountRepository = AccountRepository()) {
        self.repository = repository
    }

    var body: some View {
        ZStack {
            PaperBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    header

                    Text("delete your account and everything in it. this cannot be undone.")
                        .font(Font.Soma.pullQuote)
                        .foregroundStyle(Color.ink)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    bulletList

                    typedConfirmation

                    if let errorText {
                        Text(errorText)
                            .font(Font.Soma.margin)
                            .foregroundStyle(Color.persimmon)
                    }

                    actionRow

                    Spacer(minLength: 40)
                }
                .padding(Theme.Spacing.xl)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("DELETE ACCOUNT")
                .font(Font.Soma.sectionTag)
                .tracking(3)
                .foregroundStyle(Color.persimmon)
            Spacer()
            Button("cancel") { dismiss() }
                .font(Font.Soma.buttonLg)
                .foregroundStyle(Color.inkSoft)
                .buttonStyle(.plain)
        }
    }

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            ForEach([
                "every meal you've logged",
                "every check-in and health-day summary",
                "every insight the engine has surfaced",
                "your saved corrections and feedback",
                "the account itself — you can re-sign-in with Apple later, but it'll be a fresh start",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    Text("·")
                        .font(Font.Soma.dish)
                        .foregroundStyle(Color.persimmon)
                    Text(line)
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.ink)
                }
            }
        }
    }

    private var typedConfirmation: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("type “delete” to confirm")
                .font(Font.Soma.sectionTag)
                .tracking(2)
                .foregroundStyle(Color.persimmon)

            TextField("delete", text: $confirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Font.Soma.dishNote)
                .padding(.vertical, 10)
                .padding(.horizontal, Theme.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.indexCard, style: .continuous)
                        .strokeBorder(Color.rule, lineWidth: 0.6)
                )
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            Button {
                Task { await performDelete() }
            } label: {
                Text(isDeleting ? "deleting…" : "delete forever")
                    .font(Font.Soma.buttonLg)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(canDelete ? Color.persimmon : Color.inkSoft.opacity(0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canDelete || isDeleting)
        }
    }

    private var canDelete: Bool {
        confirmation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "delete"
    }

    private func performDelete() async {
        guard canDelete, !isDeleting else { return }
        isDeleting = true
        errorText = nil
        defer { isDeleting = false }

        // Fresh Apple authorization so the server can revoke the SIWA
        // token (Apple requires revocation alongside account deletion).
        // Best-effort: if the user cancels Apple's sheet, delete anyway —
        // 5.1.1(v) forbids blocking deletion on extra steps.
        let authCode = (try? await appleSignIn.signIn())?.authorizationCode

        do {
            try await repository.deleteAccount(authorizationCode: authCode)
            // Server has torn down the row; local sign-out clears the JWT.
            await session.signOut()
            dismiss()
        } catch {
            errorText = "couldn't delete — try again in a moment?"
        }
    }
}
