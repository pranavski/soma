-- insights: clients read, only the server writes.
--
-- The original insights migration (20260614120500) gave the owner
-- insert/update/delete policies alongside select. Every table added since
-- that carries derived findings — pattern_history, reflections — was
-- deliberately given a read-only policy, because a client that can write
-- into its own feed can manufacture evidence, and the whole product rests
-- on the feed only ever saying what the engine found. insights was never
-- brought in line. This does that.
--
-- generate-insights is the only writer, via the service role, which
-- bypasses RLS and is unaffected. The iOS client only ever selects from
-- this table (InsightsRepository.fetchRecent); nothing in the app inserts,
-- updates or deletes an insight, so no client path changes.

drop policy if exists "owner can insert" on public.insights;
drop policy if exists "owner can update" on public.insights;
drop policy if exists "owner can delete" on public.insights;
