-- Take TRUNCATE away from the client roles.
--
-- Supabase's bootstrap grants ALL privileges on every table in `public` to
-- anon and authenticated, on the understanding that RLS is what actually
-- decides who sees what. That holds for SELECT/INSERT/UPDATE/DELETE. It
-- does not hold for TRUNCATE: row-level security has no notion of "some
-- rows" for a statement that removes all of them, so Postgres does not
-- filter TRUNCATE through policies at all. The privilege alone is the
-- whole authorisation check.
--
-- So on paper every signed-in user — and every anonymous one — currently
-- holds the right to empty `meals`, `health_days`, or `insights` outright.
--
-- This is not reachable today. PostgREST exposes no TRUNCATE verb, and the
-- roles are only ever assumed through a JWT at the API layer, never as a
-- direct database login. That is why this is hygiene rather than an
-- incident. But it is a privilege nothing uses, guarding data with no
-- backup story for a single-user-per-row app, and revoking it costs
-- nothing — the only thing standing between a future RPC or a widened
-- connection path and total data loss should not be "no one has found a
-- way to say TRUNCATE yet".
--
-- service_role keeps it: the Edge Functions run as that role and it is
-- already trusted to bypass RLS entirely.

revoke truncate on all tables in schema public from anon, authenticated;

-- Existing tables are covered above; this covers tables created later, so
-- the grant does not quietly come back with the next migration. Scoped to
-- objects created by `postgres`, which is the role every migration in this
-- repo runs as and the one whose default privileges granted TRUNCATE in
-- the first place.
alter default privileges for role postgres in schema public
  revoke truncate on tables from anon, authenticated;

-- Deliberately left alone: REFERENCES and TRIGGER are also granted to the
-- client roles and also sit outside RLS. Neither is exploitable without
-- table ownership, and revoking them is a wider blast radius than this
-- migration wants to take on unprompted. Recorded here so the omission
-- reads as a decision rather than an oversight.
