-- Insight-engine pivot: generate-insights runs nightly instead of weekly.
-- The function is idempotent per user (claim_norm dedupe), so a nightly
-- fan-out only inserts when something genuinely new surfaces.
--
-- Operator setup is unchanged from 20260614120700 — the same two vault
-- secrets ('edge_function_base_url', 'insights_cron_secret') drive the
-- call, and the job no-ops with a NOTICE when either is missing.

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

  -- Fan out one async POST per user who's logged a meal in the lookback
  -- window. The Edge Function decides whether anything qualifies.
  for v_user_id in
    select distinct user_id
      from public.meals
      where eaten_at > now() - interval '30 days'
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

-- Replace the weekly job. cron.unschedule() errors on unknown names on
-- some pg_cron versions, so guard the lookup.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'generate-insights-weekly') then
    perform cron.unschedule('generate-insights-weekly');
  end if;
end;
$$;

-- 03:30 UTC nightly. cron.schedule() upserts by job name, so re-running
-- the migration replaces the existing entry.
select cron.schedule(
  'generate-insights-nightly',
  '30 3 * * *',
  $$ select private.invoke_generate_insights_nightly() $$
);

drop function if exists private.invoke_generate_insights_weekly();
