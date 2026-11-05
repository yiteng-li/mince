-- Private buckets. Objects live under '<user_id>/...'; only the owner can touch them.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('snapshots',   'snapshots',   false, 5242880, array['image/jpeg', 'image/png', 'image/heic']),
  ('meal-photos', 'meal-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/heic'])
on conflict (id) do nothing;

create policy "own objects" on storage.objects for all to authenticated
  using (bucket_id in ('snapshots', 'meal-photos') and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id in ('snapshots', 'meal-photos') and (storage.foldername(name))[1] = auth.uid()::text);
