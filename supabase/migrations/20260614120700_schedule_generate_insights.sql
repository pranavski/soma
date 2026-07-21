-- Schedule weekly per-user invocation of generate-insights.
--
-- One-time operator setup PER ENVIRONMENT (not in this migration, since the
-- values differ between environments and contain a secret):
--
--   -- in psql, after this migration has applied:
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1',
--     'edge_function_base_url'
--   );
--   select vault.create_secret(
--     '<a strong random string>',
--     'insights_cron_secret'
--   );
--
--   -- and on the Edge Function side:
--   supabase secrets set INSIGHTS_CRON_SECRET=<same string>
--
-- The cron job no-ops with a NOTICE if either secret is missing, so the
-- migration is safe to apply to a fresh environment before secrets are set.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net  with schema extensions;

create schema if not exists private;

create or replace function private.invoke_generate_insights_weekly()
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id    uuid;
  v_base_url   text;
  v_secret     text;
  v_week_start date := date_trunc('week', current_date)::date;
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
      where eaten_at > now() - interval '28 days'
  loop
    perform net.http_post(
      url := v_base_url || '/generate-insights',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_secret
      ),
      body := jsonb_build_object(
        'user_id', v_user_id,
        'week_start', v_week_start
      )
    );
  end loop;
end;
$$;

-- Monday 06:00 UTC. cron.schedule() upserts by job name, so re-running the
-- migration replaces the existing entry.
select cron.schedule(
  'generate-insights-weekly',
  '0 6 * * 1',
  $$ select private.invoke_generate_insights_weekly() $$
);
