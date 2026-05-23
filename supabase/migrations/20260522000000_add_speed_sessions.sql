-- Speed sessions: drag-strip-style measurements per vehicle.

CREATE TABLE public.speed_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  selected_metrics TEXT[] NOT NULL,
  results JSONB NOT NULL DEFAULT '{}'::jsonb,
  countdown_seconds INTEGER NOT NULL,
  is_partial BOOLEAN NOT NULL DEFAULT false,
  started_at TIMESTAMPTZ NOT NULL,
  finished_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

ALTER TABLE public.speed_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own speed sessions"
  ON public.speed_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own speed sessions"
  ON public.speed_sessions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own speed sessions"
  ON public.speed_sessions FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own speed sessions"
  ON public.speed_sessions FOR DELETE
  USING (auth.uid() = user_id);

CREATE INDEX idx_speed_sessions_user_created
  ON public.speed_sessions(user_id, created_at DESC);
