-- ai_consent: the server-side copy of the third-party-AI consent decision.
--
-- Guideline 5.1.2(i) (revised 2025-11-13) requires explicit, in-app
-- permission before personal data is shared with third-party AI. The app
-- asks (AIDisclosure) and gates parse-meal on the answer — but the answer
-- lived only in UserDefaults, and the nightly generate-insights fan-out
-- runs server-side for every user with a recent meal. A person who tapped
-- "not now" therefore still had their meals, check-ins and daily health
-- totals sent to Claude every night, which is precisely what the policy
-- and the consent sheet promise does not happen.
--
-- The app upserts its decision here on accept/decline (and re-pushes on
-- every sign-in so an earlier failed write heals). generate-insights
-- refuses to call the model without a consented row, and the cron fan-out
-- below only enqueues consented users in the first place. Absence of a
-- row means no consent.
--
-- consent_version mirrors the UserDefaults key suffix (`v1`): consent is
-- to a described flow, so a wider flow bumps the version and a stale row
-- no longer counts.

create table public.ai_consent (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  consented       boolean not null,
  consent_version text not null default 'v1',
  updated_at      timestamptz not null default now()
);

create trigger ai_consent_set_updated_at
before update on public.ai_consent
for each row execute function public.set_updated_at();

alter table public.ai_consent enable row level security;

create policy "owner can select" on public.ai_consent
  for select using ((select auth.uid()) = user_id);

create policy "owner can insert" on public.ai_consent
  for insert with check ((select auth.uid()) = user_id);

create policy "owner can update" on public.ai_consent
  for update using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Nightly fan-out: only people who have said yes. Same body as
-- 20260720120200 otherwise; cron.schedule() already points at this name.
create or replace function private.invoke_generate_insights_nightly()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id  uuid;
  v_base_url text;
  v_secret   text;
begin
  select decrypted_secret into v_base_url
    from vault.decrypted_secrets where name = 'edge_function_base_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'insights_cron_secret';

  if v_base_url is null or v_secret is null then
    raise notice 'generate-insights cron: vault secrets missing, skipping run';
    return;
  end if;

  for v_user_id in
    select distinct m.user_id
      from public.meals m
      join public.ai_consent c
        on c.user_id = m.user_id
       and c.consented
       and c.consent_version = 'v1'
      where m.eaten_at > now() - interval '30 days'
  loop
    perform net.http_post(
      url := v_base_url || '/generate-insights',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      ),
      body := jsonb_build_object('user_id', v_user_id)
    );
  end loop;
end;
$$;
