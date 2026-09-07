import Foundation

// Supabase project endpoint + anon key.
//
// The anon key is *public* (it only grants what RLS allows), so it's safe
// to ship in the iOS bundle. The SERVICE ROLE key must NEVER appear here.
//
// The values below are the hosted production project (project ref
// kfrximkdxmdqcbkjqxmb). To point a build at a local stack, swap in what
// `supabase start` prints; the anon key rotates from the dashboard.

enum SupabaseConfig {
    // Compile-time constant — Swift resolves this at build time. If the
    // URL string ever fails to parse the whole target fails to launch, which
    // is the desired failure mode (there's no meaningful runtime recovery
    // from a malformed backend endpoint).
    static let url: URL = {
        guard let url = URL(string: "https://kfrximkdxmdqcbkjqxmb.supabase.co") else {
            fatalError("SupabaseConfig.url: malformed base URL literal")
        }
        return url
    }()

    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtmcnhpbWtkeG1kcWNia2pxeG1iIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE0NDYxOTYsImV4cCI6MjA5NzAyMjE5Nn0.s4jkoyl_x6BPNd_JN9CDtXl60eqKA7ZGw2jyNA1s5o8"
}
