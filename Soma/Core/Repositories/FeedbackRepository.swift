import Foundation
import Supabase
import UIKit

/// Client-side inserts into `app_feedback`. Owner-only RLS handles both
/// authorization and user_id enforcement, so we don't need an Edge
/// Function — a plain PostgREST insert is enough.
struct FeedbackRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient = .shared) {
        self.client = client
    }

    func submit(category: FeedbackCategory, body: String) async throws {
        let userId = try await client.auth.session.user.id
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let row = FeedbackInsert(
            user_id: userId,
            category: category.rawValue,
            body: String(trimmed.prefix(4000)),
            app_version: Self.appVersion,
            os_version: Self.osVersion
        )
        try await client.from("app_feedback").insert(row).execute()
    }

    private struct FeedbackInsert: Encodable {
        let user_id: UUID
        let category: String
        let body: String
        let app_version: String?
        let os_version: String?
    }

    private static var appVersion: String? {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, _):  return s
        default:           return nil
        }
    }

    private static var osVersion: String? {
        "iOS \(UIDevice.current.systemVersion)"
    }
}

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug
    case idea
    case ai_wrong
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug:      return "bug"
        case .idea:     return "idea"
        case .ai_wrong: return "ai got it wrong"
        case .other:    return "other"
        }
    }
}
