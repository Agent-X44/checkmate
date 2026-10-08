-- Run once in the Supabase SQL Editor for an existing CheckMate database.
-- Announcements and comments are shared across devices; old local demo posts
-- are deliberately not imported.
BEGIN;

CREATE TABLE IF NOT EXISTS public.class_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.profiles(id),
  content TEXT NOT NULL CHECK (length(btrim(content)) > 0),
  allow_comments BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS class_announcements_class_created_idx
  ON public.class_announcements (class_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.announcement_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id UUID NOT NULL REFERENCES public.class_announcements(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.profiles(id),
  content TEXT NOT NULL CHECK (length(btrim(content)) > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS announcement_comments_post_created_idx
  ON public.announcement_comments (announcement_id, created_at);

ALTER TABLE public.class_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.announcement_comments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.class_announcements, public.announcement_comments
  FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.class_announcements
  TO authenticated;
GRANT SELECT, INSERT ON public.announcement_comments TO authenticated;

DROP POLICY IF EXISTS "Class members read announcements" ON public.class_announcements;
CREATE POLICY "Class members read announcements" ON public.class_announcements
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.classes c
          WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.enrollments e
             WHERE e.class_id = class_announcements.class_id AND e.user_id = auth.uid()
               AND e.role = 'Student')
);

DROP POLICY IF EXISTS "Instructor creates announcements" ON public.class_announcements;
CREATE POLICY "Instructor creates announcements" ON public.class_announcements
FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (SELECT 1 FROM public.classes c
              WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
);

DROP POLICY IF EXISTS "Instructor updates announcements" ON public.class_announcements;
CREATE POLICY "Instructor updates announcements" ON public.class_announcements
FOR UPDATE TO authenticated
USING (author_id = auth.uid() AND EXISTS (
  SELECT 1 FROM public.classes c
  WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid()))
WITH CHECK (author_id = auth.uid() AND EXISTS (
  SELECT 1 FROM public.classes c
  WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid()));

DROP POLICY IF EXISTS "Instructor deletes announcements" ON public.class_announcements;
CREATE POLICY "Instructor deletes announcements" ON public.class_announcements
FOR DELETE TO authenticated USING (
  author_id = auth.uid() AND EXISTS (
    SELECT 1 FROM public.classes c
    WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
);

DROP POLICY IF EXISTS "Class members read announcement comments" ON public.announcement_comments;
CREATE POLICY "Class members read announcement comments" ON public.announcement_comments
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.class_announcements a
          WHERE a.id = announcement_comments.announcement_id)
);

DROP POLICY IF EXISTS "Class members add enabled comments" ON public.announcement_comments;
CREATE POLICY "Class members add enabled comments" ON public.announcement_comments
FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM public.class_announcements a
    WHERE a.id = announcement_comments.announcement_id AND a.allow_comments
      AND (EXISTS (SELECT 1 FROM public.classes c
                   WHERE c.id = a.class_id AND c.instructor_id = auth.uid())
           OR EXISTS (SELECT 1 FROM public.enrollments e
                      WHERE e.class_id = a.class_id
                        AND e.user_id = auth.uid() AND e.role = 'Student'))
  )
);

COMMIT;
