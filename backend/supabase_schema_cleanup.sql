-- Remove confirmed unused database structure from an existing CheckMate DB.
-- Deploy the updated backend/app first; see DATABASE_CLEANUP.md.
-- Existing users, classes, enrollments, assessments, questions and grades stay.
-- This transaction refuses to remove meaningful legacy data or dependencies.
BEGIN;

-- Prevent legacy data from appearing between the checks and column removal.
LOCK TABLE public.profiles, public.exams, public.answer_sheets IN ACCESS EXCLUSIVE MODE;

DO $$
DECLARE
  has_legacy_data BOOLEAN;
  legacy_functions TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'grades'
      AND column_name = 'student_insight'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'grades'
      AND column_name = 'answers'
  ) THEN
    RAISE EXCEPTION 'Apply supabase_result_details.sql before schema cleanup';
  END IF;

  -- PL/pgSQL bodies can refer to old fields without catalog dependencies.
  -- The signup function is the one known dependency replaced below. Refuse
  -- other explicit legacy references rather than leaving broken custom RPCs.
  SELECT string_agg(p.oid::regprocedure::TEXT, ', ' ORDER BY p.oid::regprocedure::TEXT)
    INTO legacy_functions
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
    AND p.proname <> 'handle_new_user'
    AND (
      p.prosrc ~* '\mai_insights\M|\mquestion_structure\M|\mscanned_at\M'
      OR (p.prosrc ~* '\mprofiles\M' AND p.prosrc ~* '\mrole\M')
      OR EXISTS (
        SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
        JOIN pg_namespace s ON s.oid = c.relnamespace
        WHERE t.tgfoid = p.oid AND NOT t.tgisinternal AND s.nspname = 'public'
          AND ((c.relname = 'profiles' AND p.prosrc ~* '\m(NEW|OLD)\.role\M')
            OR (c.relname = 'answer_sheets' AND p.prosrc ~* '\m(NEW|OLD)\.status\M'))
      )
    );
  IF legacy_functions IS NOT NULL THEN
    RAISE EXCEPTION 'Review functions referencing retired schema before cleanup: %', legacy_functions;
  END IF;

  -- The current application never reads/writes this table. Still refuse to
  -- discard any older insight records that may exist in another installation.
  IF to_regclass('public.ai_insights') IS NOT NULL THEN
    EXECUTE 'LOCK TABLE public.ai_insights IN ACCESS EXCLUSIVE MODE';
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.ai_insights)' INTO has_legacy_data;
    IF has_legacy_data THEN
      RAISE EXCEPTION 'ai_insights contains legacy records; review them before cleanup';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'exams'
      AND column_name = 'question_structure') THEN
    EXECUTE $check$
      SELECT EXISTS (SELECT 1 FROM public.exams
        WHERE question_structure IS NOT NULL
          AND question_structure NOT IN ('null'::jsonb, '{}'::jsonb, '[]'::jsonb))
    $check$ INTO has_legacy_data;
    IF has_legacy_data THEN
      RAISE EXCEPTION 'exams.question_structure contains legacy data; review it before cleanup';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'answer_sheets'
      AND column_name = 'status') THEN
    EXECUTE $check$
      SELECT EXISTS (SELECT 1 FROM public.answer_sheets
        WHERE status IS NOT NULL AND btrim(status) NOT IN ('', 'Pending'))
    $check$ INTO has_legacy_data;
    IF has_legacy_data THEN
      RAISE EXCEPTION 'answer_sheets.status contains nondefault legacy data; review it before cleanup';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'answer_sheets'
      AND column_name = 'scanned_at') THEN
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM public.answer_sheets WHERE scanned_at IS NOT NULL)'
      INTO has_legacy_data;
    IF has_legacy_data THEN
      RAISE EXCEPTION 'answer_sheets.scanned_at contains legacy data; review it before cleanup';
    END IF;
  END IF;
END $$;

-- Keep email/password and Google signups working without an account-wide role.
-- Creator/enrollee roles remain in classes.instructor_id and enrollments.role.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email)
  VALUES (NEW.id, coalesce(
    nullif(btrim(NEW.raw_user_meta_data->>'name'), ''),
    nullif(btrim(NEW.raw_user_meta_data->>'full_name'), ''),
    nullif(split_part(NEW.email, '@', 1), ''), 'User'), NEW.email);
  RETURN NEW;
END;
$$;

-- RESTRICT aborts rather than deleting unexpected views/policies/dependents.
DROP TABLE IF EXISTS public.ai_insights RESTRICT;
ALTER TABLE public.profiles DROP COLUMN IF EXISTS role RESTRICT;
ALTER TABLE public.exams DROP COLUMN IF EXISTS question_structure RESTRICT;
ALTER TABLE public.answer_sheets DROP COLUMN IF EXISTS status RESTRICT;
ALTER TABLE public.answer_sheets DROP COLUMN IF EXISTS scanned_at RESTRICT;

NOTIFY pgrst, 'reload schema';
COMMIT;
