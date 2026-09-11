-- Storage buckets:
--   drawings           private — children's drawing images/thumbnails
--   specialist-photos   public read — specialist avatars/illustrations
--   story-covers        public read — curated story cover art
--
-- `drawings` is the one bucket the Flutter client uploads to directly,
-- so it's the one that needs abuse limits: a 5 MB cap comfortably
-- covers a 2x-pixel-ratio PNG capture of a full drawing canvas (a
-- typical export is well under 1-2 MB even for a busy, colorful
-- drawing) while still bounding a buggy or malicious client's worst
-- case. Allowed types cover every format the app or a future client
-- might reasonably export a drawing as; `image/jpg` is included
-- alongside the correct `image/jpeg` because some client libraries
-- report the non-standard variant.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'drawings',
    'drawings',
    false,
    5242880,
    array['image/png', 'image/jpeg', 'image/jpg', 'image/webp']
  )
on conflict (id) do nothing;

-- specialist-photos / story-covers are admin-uploaded only (via the
-- service role), so no client-facing size/type limit is set here.
insert into storage.buckets (id, name, public)
values
  ('specialist-photos', 'specialist-photos', true),
  ('story-covers', 'story-covers', true)
on conflict (id) do nothing;

-- drawings: private. Path convention is
--   {parent_id}/{child_id}/{drawing_id}.png
-- so the first folder segment can be checked against auth.uid()
-- directly. No update policy (matches the drawings table's
-- immutability).
create policy "Parents can view their own drawing files"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Parents can upload their own drawing files"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Parents can delete their own drawing files"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'drawings'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- specialist-photos / story-covers: public read. No insert/update/
-- delete policy is created for these buckets — uploads happen only
-- via the service role (admin content management), never the client.
create policy "Anyone can view specialist photos"
  on storage.objects for select
  using (bucket_id = 'specialist-photos');

create policy "Anyone can view story covers"
  on storage.objects for select
  using (bucket_id = 'story-covers');
