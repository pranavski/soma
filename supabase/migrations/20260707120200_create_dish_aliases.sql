-- dish_aliases: community-shared canonical-name ↔ alias table.
--
-- When one user corrects "chana masala" → "chole" (a common alias in
-- North India), we increment a row here so the next user who types
-- "chole" gets grounded to "chana masala". This is the ONLY cross-user
-- signal in the retrieval system — deliberately kept to a benign,
-- de-identified name-only mapping. No macros, no photos, no per-user
-- data ever land here.
--
-- Reads: all authenticated users can select (parse-meal fetches top
-- ~50 by sample_count regardless of caller). Writes: service role only
-- via the submit-correction Edge Function, which sanitises input and
-- upserts atomically.

create table public.dish_aliases (
  id             uuid primary key default gen_random_uuid(),
  canonical_name text not null,
  alias          text not null,
  cuisine        text
    check (cuisine is null or cuisine in (
      'south_asian','east_asian','southeast_asian','middle_eastern',
      'mediterranean','african','latin_american','caribbean',
      'western','other'
    )),
  confidence     real not null default 0.5
                 check (confidence >= 0 and confidence <= 1),
  sample_count   int  not null default 1
                 check (sample_count >= 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- One row per (canonical, alias) pair — the upsert in submit-correction
-- targets this uniqueness.
create unique index dish_aliases_canonical_alias_key
  on public.dish_aliases (lower(canonical_name), lower(alias));

create index dish_aliases_sample_desc_idx
  on public.dish_aliases (sample_count desc);

create trigger dish_aliases_set_updated_at
before update on public.dish_aliases
for each row execute function public.set_updated_at();

alter table public.dish_aliases enable row level security;

-- Read: any signed-in user. Rows are name mappings only, no PII.
create policy "authenticated can read" on public.dish_aliases
  for select
  to authenticated
  using (true);

-- No insert/update/delete policies for the anon or authenticated roles.
-- Service role bypasses RLS entirely — the submit-correction Edge
-- Function is the ONLY writer, and it revalidates every field before
-- upserting.
