-- Private bucket for meal photos. Path layout enforced by the iOS client
-- and the parse-meal Edge Function: <user_id>/<meal_id>.<ext>.
-- Reads happen via short-TTL signed URLs; the bucket itself stays private.

insert into storage.buckets (id, name, public)
values ('meal-photos', 'meal-photos', false)
on conflict (id) do nothing;

-- Owner-only access on storage.objects, scoped to this bucket.
-- (storage.foldername(name))[1] returns the first path segment, which the
-- client always sets to the user's auth.uid().

create policy "meal-photos owner can read"
  on storage.objects for select
  using (
    bucket_id = 'meal-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "meal-photos owner can insert"
  on storage.objects for insert
  with check (
    bucket_id = 'meal-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "meal-photos owner can update"
  on storage.objects for update
  using (
    bucket_id = 'meal-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "meal-photos owner can delete"
  on storage.objects for delete
  using (
    bucket_id = 'meal-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );
