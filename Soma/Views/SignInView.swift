import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var isWorking = false
    @State private var showPrivacy = false

    var body: some View {
        ZStack {
            PaperBackground()

            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Spacer()

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("WELCOME")
                        .font(Font.Soma.sectionTag)
                        .tracking(3)
                        .foregroundStyle(Color.inkSoft)

                    HStack(spacing: 0) {
                        Text("Soma")
                            .font(Font.Soma.logo)
                            .foregroundStyle(Color.ink)
                        Text(".")
                            .font(Font.Soma.logo)
                            .foregroundStyle(Color.persimmon)
                    }
                }

                Text("a quiet record of\nwhat you eat, and\nhow you feel.")
                    .font(Font.Soma.dayLine)
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)

                HStack(spacing: Theme.Spacing.s) {
                    InkRule(style: .wavy,
                            color: Color.rule,
                            weight: Theme.Stroke.hairline + 0.4)
                        .frame(width: 60)
                    Text("ten seconds. no goals.")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft)
                }

                Spacer()

                AppleSignInButton(isWorking: isWorking) {
                    Task {
                        isWorking = true
                        await session.signInWithApple()
                        isWorking = false
                    }
                }

                if let err = session.errorText {
                    Text(err)
                        .font(Font.Soma.dishNote)
                        .foregroundStyle(Color.persimmon)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("by signing in you accept that this isn't medical advice.")
                        .font(Font.Soma.margin)
                        .foregroundStyle(Color.inkSoft.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    // 5.1.1(i) wants the policy reachable in the app. Putting
                    // it here as well as in the kitchen means a reviewer meets
                    // it before creating an account, not after.
                    Button { showPrivacy = true } label: {
                        Text("privacy policy")
                            .font(Font.Soma.margin)
                            .underline()
                            .foregroundStyle(Color.inkSoft)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, Theme.Spacing.l)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyPolicySheet()
        }
    }
}

/// Apple's own button class so the rendering is exactly HIG-compliant
/// (guideline 4.8) — approved logo art, title casing, and contrast. The
/// tap still routes through SessionStore's existing coordinator flow.
private struct AppleSignInButton: View {
    let isWorking: Bool
    var action: () -> Void

    var body: some View {
        ZStack {
            AppleIDButtonRepresentable(action: action)
                .frame(height: 50)
                .opacity(isWorking ? 0.5 : 1)
                .allowsHitTesting(!isWorking)
                .shadow(color: Color.paperShadow.opacity(0.6), radius: 18, x: 0, y: 12)

            if isWorking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.paper)
            }
        }
        .accessibilityLabel("Sign in with Apple")
    }
}

private struct AppleIDButtonRepresentable: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .black)
        button.cornerRadius = 25
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

#Preview {
    SignInView()
        .environmentObject(SessionStore())
}
