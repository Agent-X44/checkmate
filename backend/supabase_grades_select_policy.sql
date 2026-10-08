-- Apply after supabase_answer_sheets_policies.sql on existing databases.
-- Safe to rerun; preserves the student policy for own released results.
BEGIN;
ALTER TABLE public.grades ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Instructors view own class grades" ON public.grades;
-- Instructors can review grades for their own classes before release.
CREATE POLICY "Instructors view own class grades" ON public.grades
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.answer_sheets s
    JOIN public.exams e ON e.id = s.exam_id
    JOIN public.classes c ON c.id = e.class_id
    WHERE s.id = grades.sheet_id
      AND c.instructor_id = auth.uid()
  )
);
COMMIT;
