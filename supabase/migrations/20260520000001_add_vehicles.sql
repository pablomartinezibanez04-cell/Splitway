-- Garage: vehicles table for user vehicle management

CREATE TABLE public.vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'car',
  photo_url TEXT,
  model TEXT,
  year INTEGER,
  horsepower INTEGER,
  torque_nm INTEGER,
  weight_kg INTEGER,
  drivetrain TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own vehicles"
  ON public.vehicles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own vehicles"
  ON public.vehicles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own vehicles"
  ON public.vehicles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own vehicles"
  ON public.vehicles FOR DELETE
  USING (auth.uid() = user_id);

CREATE INDEX idx_vehicles_user_id ON public.vehicles(user_id);

-- Storage bucket for vehicle photos (created via Supabase dashboard or CLI)
-- Bucket name: vehicle-photos
-- Public: false
-- File size limit: 5MB
-- Allowed MIME types: image/*

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('vehicle-photos', 'vehicle-photos', false, 5242880, ARRAY['image/*'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Users can upload vehicle photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'vehicle-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can update own vehicle photos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'vehicle-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can delete own vehicle photos"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'vehicle-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "Users can view own vehicle photos"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'vehicle-photos'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
