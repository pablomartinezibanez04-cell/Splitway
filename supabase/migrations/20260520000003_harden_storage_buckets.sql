-- Harden storage buckets: restrict MIME types to safe image formats only
-- and add missing size limit on avatars bucket.
--
-- Fixes:
--   - vehicle-photos used image/* which accepts SVG (XSS vector), TIFF, BMP, etc.
--   - avatars had no file_size_limit or allowed_mime_types at all.

UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'vehicle-photos';

UPDATE storage.buckets
SET file_size_limit = 2097152,  -- 2 MB
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'avatars';
