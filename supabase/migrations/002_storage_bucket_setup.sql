-- Storage bucket setup for recipe-photos
-- Private bucket, gated by user_id: objects are stored at path
-- {user_id}/{filename}, so the first folder segment doubles as the
-- access-control key (same pattern as Houstory's houstory-media bucket).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'recipe-photos',
  'recipe-photos',
  false,
  10485760, -- 10MB
  ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/heic', 'image/webp'];

CREATE POLICY "Users can read their own recipe photos" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'recipe-photos'
    AND (storage.foldername(name))[1]::uuid = auth.uid()
  );

CREATE POLICY "Users can upload their own recipe photos" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'recipe-photos'
    AND (storage.foldername(name))[1]::uuid = auth.uid()
  );

CREATE POLICY "Users can delete their own recipe photos" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'recipe-photos'
    AND (storage.foldername(name))[1]::uuid = auth.uid()
  );
