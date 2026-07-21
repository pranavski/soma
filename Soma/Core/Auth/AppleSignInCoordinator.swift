import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct AppleSignInResult {
    let identityToken: String
    let rawNonce: String
    /// Single-use code the server can exchange with Apple to revoke the
    /// sign-in token (required for account deletion). Valid ~5 minutes.
    let authorizationCode: String?
}

enum AppleSignInError: LocalizedError {
    case canceled
    case missingIdentityToken
    case invalidIdentityToken

    var errorDescription: String? {
        switch self {
        case .canceled:             return "Sign in canceled."
        case .missingIdentityToken: return "Apple didn't return an identity token."
        case .invalidIdentityToken: return "Apple identity token couldn't be read."
        }
    }
}

/// Drives the Sign-in-with-Apple flow and returns the identity token + raw
/// nonce, which the caller hands to Supabase's `signInWithIdToken`.
///
/// Apple's request gets the *hashed* nonce; Supabase verifies against the
/// *raw* nonce — that pair-up is the only reason we keep the value around.
final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var currentNonce: String?

    @MainActor
    func signIn() async throws -> AppleSignInResult {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    // MARK: Nonce

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        var out = ""
        out.reserveCapacity(length)
        if status == errSecSuccess {
            for byte in bytes {
                out.append(charset[Int(byte) % charset.count])
            }
        } else {
            for _ in 0..<length {
                out.append(charset.randomElement() ?? "0")
            }
        }
        return out
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { cleanup() }

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce
        else {
            continuation?.resume(throwing: AppleSignInError.canceled)
            return
        }

        guard let tokenData = credential.identityToken else {
            continuation?.resume(throwing: AppleSignInError.missingIdentityToken)
            return
        }

        guard let token = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(throwing: AppleSignInError.invalidIdentityToken)
            return
        }

        let code = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        continuation?.resume(
            returning: AppleSignInResult(
                identityToken: token,
                rawNonce: nonce,
                authorizationCode: code
            )
        )
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        defer { cleanup() }

        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            continuation?.resume(throwing: AppleSignInError.canceled)
        } else {
            continuation?.resume(throwing: error)
        }
    }

    private func cleanup() {
        continuation = nil
        currentNonce = nil
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        return window ?? ASPresentationAnchor()
    }
}
