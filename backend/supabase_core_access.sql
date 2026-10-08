-- Apply to an existing CheckMate database after the result-detail migration.
-- The answer key and any remaining legacy AI records must not be readable by students.
BEGIN;

-- RLS policies combine permissively. Refuse to claim the key is protected if
-- an unreviewed policy could still grant broader read access.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'questions'
      AND policyname NOT IN (
        'Service Role Full Access on questions',
        'Instructors manage own questions')
  ) OR EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'ai_insights'
      AND policyname NOT IN (
        'Instructors manage own AI insights',
        'Students read own released AI insights')
  ) THEN
    RAISE EXCEPTION 'Review existing questions/ai_insights policies before applying this migration';
  END IF;
END $$;

ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;

-- Until the legacy table is retired, keep its unreleased student evaluations
-- inaccessible to app clients. The SQL Editor and service role can still
-- perform the verified backfill.
DO $$
BEGIN
  IF to_regclass('public.answers') IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.answers ENABLE ROW LEVEL SECURITY';
    EXECUTE 'REVOKE ALL ON TABLE public.answers FROM PUBLIC, anon, authenticated';
  END IF;
END $$;

DROP POLICY IF EXISTS "Instructors manage own questions" ON public.questions;
CREATE POLICY "Instructors manage own questions" ON public.questions
FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.exams e
  JOIN public.classes c ON c.id = e.class_id
  WHERE e.id = questions.exam_id AND c.instructor_id = auth.uid()
))
WITH CHECK (EXISTS (
  SELECT 1 FROM public.exams e
  JOIN public.classes c ON c.id = e.class_id
  WHERE e.id = questions.exam_id AND c.instructor_id = auth.uid()
));

-- New/cleaned schemas store personal feedback in grades.student_insight.
-- Protect this old table only while it still exists before verified cleanup.
DO $$ BEGIN
  IF to_regclass('public.ai_insights') IS NOT NULL THEN
    ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Instructors manage own AI insights" ON public.ai_insights;
    CREATE POLICY "Instructors manage own AI insights" ON public.ai_insights
    FOR ALL TO authenticated
    USING (EXISTS (
      SELECT 1 FROM public.exams e
      JOIN public.classes c ON c.id = e.class_id
      WHERE e.id = ai_insights.exam_id AND c.instructor_id = auth.uid()
    ))
    WITH CHECK (EXISTS (
      SELECT 1 FROM public.exams e
      JOIN public.classes c ON c.id = e.class_id
      WHERE e.id = ai_insights.exam_id AND c.instructor_id = auth.uid()
    ));

    DROP POLICY IF EXISTS "Students read own released AI insights" ON public.ai_insights;
    CREATE POLICY "Students read own released AI insights" ON public.ai_insights
    FOR SELECT TO authenticated
    USING (
      student_id = auth.uid()
      AND EXISTS (
        SELECT 1 FROM public.exams e
        WHERE e.id = ai_insights.exam_id AND e.results_released = TRUE
      )
    );
  END IF;
END $$;

COMMIT;
