-- Apply only after supabase_result_details.sql and verifying itemized results.
-- This is deliberately separate from the additive migrations. The transaction
-- aborts unless every old row is represented in grades.answers.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.answers') IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'grades'
      AND column_name = 'answers'
  ) THEN
    RAISE EXCEPTION 'Run supabase_result_details.sql first: grades.answers does not exist';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.answers a
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.grades g
      CROSS JOIN LATERAL jsonb_array_elements(g.answers) AS item(value)
      WHERE g.sheet_id = a.sheet_id
        AND (item.value->>'question_id') = a.question_id::text
        AND (item.value->>'answer') IS NOT DISTINCT FROM a.selected_answer
        AND (item.value->>'isCorrect')::boolean IS NOT DISTINCT FROM a.is_correct
    )
  ) THEN
    RAISE EXCEPTION 'Some legacy answers are not represented in grades.answers; old table was kept';
  END IF;
END $$;

-- RESTRICT is intentional: if another database object still depends on this
-- table, the entire transaction rolls back instead of removing that object.
DROP TABLE IF EXISTS public.answers RESTRICT;

COMMIT;
