-- Apply this additive migration before deploying the result-detail update.
-- Older scores are retained. Legacy item rows are copied when available;
-- missing item answers cannot be reconstructed from a total score alone.
BEGIN;
ALTER TABLE public.grades
  ADD COLUMN IF NOT EXISTS answers JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS student_insight JSONB;

-- Older deployments may have a separate answers table. Preserve its item
-- evaluations in the grade record used by the current app before retiring it.
-- Legacy rows do not record printed set order, so no question_number is invented.
DO $$
BEGIN
  IF to_regclass('public.answers') IS NOT NULL THEN
    EXECUTE $backfill$
      UPDATE public.grades AS g
      SET answers = legacy.items
      FROM (
        SELECT a.sheet_id,
               jsonb_agg(jsonb_build_object(
                 'question_id', a.question_id,
                 'question_text', q.question_text,
                 'question_type', q.question_type,
                 'topic_tag', q.topic_tag,
                 'answer', a.selected_answer,
                 'correct_answer', q.correct_answer,
                 'isCorrect', a.is_correct,
                 'confidence', a.confidence
               ) ORDER BY q.created_at NULLS LAST, q.id, a.id) AS items
        FROM public.answers AS a
        LEFT JOIN public.questions AS q ON q.id = a.question_id
        GROUP BY a.sheet_id
      ) AS legacy
      WHERE g.sheet_id = legacy.sheet_id
        AND (g.answers IS NULL OR g.answers = '[]'::jsonb)
    $backfill$;
  END IF;
END $$;

-- These columns inherit the same release/ownership protection as the score.
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Instructors view own class grades" ON public.grades;
CREATE POLICY "Instructors view own class grades" ON public.grades
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.answer_sheets s
  JOIN public.exams e ON e.id = s.exam_id
  JOIN public.classes c ON c.id = e.class_id
  WHERE s.id = grades.sheet_id AND c.instructor_id = auth.uid()
));
DROP POLICY IF EXISTS "Students see own released grades" ON public.grades;
CREATE POLICY "Students see own released grades" ON public.grades
FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.answer_sheets s
  JOIN public.exams e ON e.id = s.exam_id
  WHERE s.id = grades.sheet_id AND s.student_id = auth.uid()
    AND e.results_released = TRUE
));

-- One RPC call is one database transaction: a failed item rolls back the
-- entire session so class analysis cannot see a partially saved batch.
CREATE OR REPLACE FUNCTION public.save_grade_session(p_results JSONB)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  item RECORD;
  saved_count INTEGER := 0;
BEGIN
  FOR item IN
    SELECT * FROM pg_catalog.jsonb_to_recordset(p_results) AS r(
      sheet_id UUID, score INTEGER, total_questions INTEGER,
      percentage DOUBLE PRECISION, answers JSONB
    ) ORDER BY sheet_id
  LOOP
    -- Serialize retries for each sheet without requiring a destructive
    -- cleanup of legacy duplicate grade rows.
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(item.sheet_id::TEXT, 0));
    UPDATE public.grades SET
      score = item.score, total_questions = item.total_questions,
      percentage = item.percentage, answers = item.answers,
      student_insight = NULL
    WHERE sheet_id = item.sheet_id;
    IF NOT FOUND THEN
      INSERT INTO public.grades(sheet_id, score, total_questions, percentage, answers)
      VALUES (item.sheet_id, item.score, item.total_questions, item.percentage, item.answers);
    END IF;
    saved_count := saved_count + 1;
  END LOOP;
  RETURN saved_count;
END;
$$;
-- Only the authenticated/authorized FastAPI service can write a session.
REVOKE ALL ON FUNCTION public.save_grade_session(JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_grade_session(JSONB) TO service_role;
COMMIT;
