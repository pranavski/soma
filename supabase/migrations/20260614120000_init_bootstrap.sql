-- Bootstrap: extensions and shared trigger function.
-- Idempotent on purpose so a fresh local stack matches the first remote apply.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
