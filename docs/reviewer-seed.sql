-- Reviewer seed: thirty days of meals, check-ins and daily health totals
-- for ONE account, so the Noticed tab has something to show.
--
-- Why this exists: generate-insights needs ~7 meal days and ~7 body days
-- before it scores anything (digest.ts MIN_MEAL_DAYS / MIN_BODY_DAYS), and
-- App Review tests on a fresh account. Sign-in is Apple-only, so there is
-- no demo login to hand over; instead, seed your own account, record the
-- Noticed tab, and attach the video to the submission (see
-- docs/app-store-connect-copy.md → App Review notes).
--
-- What it plants: a real pattern the engine can find. Dinner alternates
-- late (21–22h) and early (18–19h); late nights sleep ~45 min less. Every
-- third day has a 3pm coffee; those nights sleep ~25 min less again.
-- Energy tracks sleep. Everything else is jittered noise.
--
-- Verified 2026-09-07 by applying the migrations to a scratch Postgres,
-- running this twice (idempotent: 100 meals, 30 health days, 30
-- check-ins) and pushing the rows through scoreAssociations() from
-- candidates.ts: 18 pairings tested, 5 survive the FDR — last meal hour
-- against sleep (rho -0.87), energy and HRV, calories against energy, and
-- late caffeine against sleep. The model then picks which to say.
--
-- Safe to re-run: seeded meals carry notes = 'reviewer-seed' and are
-- deleted first; health_days and daily_checkins are upserted by day.
-- It touches ONLY the account named below.
--
-- How to run (Supabase SQL editor, or `supabase db query -f`):
--   1. set v_email (or v_user directly) and v_tz below
--   2. run
--   3. either pull-to-refresh on the Noticed tab, or
--        curl -X POST https://<ref>.supabase.co/functions/v1/generate-insights \
--          -H "Authorization: Bearer $INSIGHTS_CRON_SECRET" \
--          -H "Content-Type: application/json" -d '{"user_id":"<uuid>"}'
--   4. delete the seed afterwards:
--        delete from public.meals where user_id = '<uuid>' and notes = 'reviewer-seed';
--        delete from public.health_days where user_id = '<uuid>' and day >= current_date - 31;
--        delete from public.daily_checkins where user_id = '<uuid>' and check_date >= current_date - 31;
--        delete from public.insights where user_id = '<uuid>';

do $$
declare
  v_email text := 'REPLACE_ME@privaterelay.appleid.com';   -- the account to seed
  v_user  uuid := null;                                    -- or set this directly
  v_tz    text := 'America/Los_Angeles';                   -- the phone's timezone

  v_day        date;
  v_d          int;
  v_late       boolean;
  v_coffee     boolean;
  v_dinner_h   int;
  v_sleep      int;
  v_energy     int;
  v_meal_id    uuid;
  v_eaten_at   timestamptz;
begin
  if v_user is null then
    select id into v_user from auth.users where email = v_email;
  end if;
  if v_user is null then
    raise exception 'no user for % — set v_user', v_email;
  end if;

  -- Consent, so the nightly job and pull-to-refresh actually run.
  insert into public.ai_consent (user_id, consented, consent_version)
  values (v_user, true, 'v1')
  on conflict (user_id) do update set consented = true, consent_version = 'v1';

  delete from public.meals where user_id = v_user and notes = 'reviewer-seed';

  for v_d in 1..30 loop
    v_day      := current_date - v_d;
    v_late     := (v_d % 2 = 0);
    v_coffee   := (v_d % 3 = 0);
    v_dinner_h := case when v_late then 21 + (v_d % 2) else 18 + (v_d % 2) end;
    v_sleep    := 465
                  - (case when v_late   then 45 else 0 end)
                  - (case when v_coffee then 25 else 0 end)
                  + ((v_d * 7) % 23) - 11;                 -- ±11 min jitter
    v_energy   := greatest(1, least(5, 2 + (v_sleep - 380) / 35));

    -- breakfast
    v_eaten_at := (v_day::text || ' 08:15')::timestamp at time zone v_tz;
    insert into public.meals (user_id, eaten_at, logged_at, source, voice_transcript, dish_name,
      calories_low, calories_high, protein_g_low, protein_g_high, fiber_g_low, fiber_g_high,
      caffeine_mg_low, caffeine_mg_high, parse_status, parsed_at, eaten_date, eaten_hour, notes)
    values (v_user, v_eaten_at, v_eaten_at, 'voice', 'two eggs on sourdough and a black coffee', 'eggs on sourdough, black coffee',
      380, 480, 18, 24, 2, 4, 80, 120, 'parsed', v_eaten_at, v_day, 8, 'reviewer-seed')
    returning id into v_meal_id;
    insert into public.meal_items (meal_id, user_id, name, quantity, position) values
      (v_meal_id, v_user, 'fried eggs', '2', 0),
      (v_meal_id, v_user, 'sourdough toast', '1 slice', 1),
      (v_meal_id, v_user, 'black coffee', '1 cup', 2);

    -- lunch
    v_eaten_at := (v_day::text || ' 13:05')::timestamp at time zone v_tz;
    insert into public.meals (user_id, eaten_at, logged_at, source, voice_transcript, dish_name,
      calories_low, calories_high, protein_g_low, protein_g_high, fiber_g_low, fiber_g_high,
      parse_status, parsed_at, eaten_date, eaten_hour, notes)
    values (v_user, v_eaten_at, v_eaten_at, 'voice',
      case when v_d % 2 = 0 then 'chana masala with rice' else 'lentil soup and a roll' end,
      case when v_d % 2 = 0 then 'chana masala, rice' else 'lentil soup, bread roll' end,
      520, 680, 16, 22, 10, 14, 'parsed', v_eaten_at, v_day, 13, 'reviewer-seed')
    returning id into v_meal_id;
    insert into public.meal_items (meal_id, user_id, name, quantity, position) values
      (v_meal_id, v_user, case when v_d % 2 = 0 then 'chana masala' else 'lentil soup' end, '1 bowl', 0),
      (v_meal_id, v_user, case when v_d % 2 = 0 then 'basmati rice' else 'bread roll' end, '1', 1);

    -- 3pm coffee, every third day
    if v_coffee then
      v_eaten_at := (v_day::text || ' 15:20')::timestamp at time zone v_tz;
      insert into public.meals (user_id, eaten_at, logged_at, source, voice_transcript, dish_name,
        calories_low, calories_high, caffeine_mg_low, caffeine_mg_high,
        parse_status, parsed_at, eaten_date, eaten_hour, notes)
      values (v_user, v_eaten_at, v_eaten_at, 'voice', 'a flat white', 'flat white',
        90, 140, 100, 150, 'parsed', v_eaten_at, v_day, 15, 'reviewer-seed')
      returning id into v_meal_id;
      insert into public.meal_items (meal_id, user_id, name, quantity, position) values
        (v_meal_id, v_user, 'flat white', '1', 0);
    end if;

    -- dinner, early or late
    v_eaten_at := (v_day::text || ' ' || lpad(v_dinner_h::text, 2, '0') || ':30')::timestamp at time zone v_tz;
    insert into public.meals (user_id, eaten_at, logged_at, source, voice_transcript, dish_name,
      calories_low, calories_high, protein_g_low, protein_g_high, fiber_g_low, fiber_g_high,
      parse_status, parsed_at, eaten_date, eaten_hour, notes)
    values (v_user, v_eaten_at, v_eaten_at, 'voice',
      case when v_d % 3 = 0 then 'roast chicken thighs with potatoes and greens'
           when v_d % 3 = 1 then 'salmon, rice, cucumber salad'
           else 'pasta with tomato and a bit of parmesan' end,
      case when v_d % 3 = 0 then 'roast chicken, potatoes, greens'
           when v_d % 3 = 1 then 'salmon, rice, cucumber salad'
           else 'tomato pasta' end,
      600, 800, 28, 40, 5, 9, 'parsed', v_eaten_at, v_day, v_dinner_h, 'reviewer-seed')
    returning id into v_meal_id;
    insert into public.meal_items (meal_id, user_id, name, quantity, position) values
      (v_meal_id, v_user, case when v_d % 3 = 0 then 'roast chicken thigh' when v_d % 3 = 1 then 'salmon fillet' else 'pasta' end, '1 plate', 0);

    -- the body's side of the day
    insert into public.health_days (user_id, day, steps, sleep_minutes, resting_hr_bpm, hrv_ms,
      weight_kg, active_energy_kcal, workout_minutes, tier, synced_at)
    values (v_user, v_day,
      6800 + ((v_d * 131) % 3500),
      v_sleep,
      56 + ((v_d * 3) % 5) + (case when v_late then 1 else 0 end),
      48 + ((v_d * 5) % 9) - (case when v_late then 3 else 0 end),
      72.4 + (((v_d * 17) % 7) - 3) * 0.1,
      380 + ((v_d * 47) % 260),
      case when v_d % 4 = 1 then 35 else 0 end,
      2, now())
    on conflict (user_id, day) do update set
      steps = excluded.steps, sleep_minutes = excluded.sleep_minutes,
      resting_hr_bpm = excluded.resting_hr_bpm, hrv_ms = excluded.hrv_ms,
      weight_kg = excluded.weight_kg, active_energy_kcal = excluded.active_energy_kcal,
      workout_minutes = excluded.workout_minutes, tier = excluded.tier, synced_at = now();

    insert into public.daily_checkins (user_id, check_date, energy)
    values (v_user, v_day, v_energy)
    on conflict (user_id, check_date) do update set energy = excluded.energy;
  end loop;

  raise notice 'seeded 30 days for %', v_user;
end $$;
