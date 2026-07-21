import Foundation
import Supabase

extension SupabaseClient {
    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    storage: KeychainAuthStorage()
                )
            )
        )
    }()
}
