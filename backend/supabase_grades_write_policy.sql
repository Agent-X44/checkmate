-- Allows the signed-in instructor to write grades for answer sheets in their
-- own classes directly from the app. This powers the client-side fallback used
-- when the FastAPI backend cannot save the scanning session.
-- Apply this in the Supabase SQL Editor, then apply
-- supabase_result_details.sql (answers / student_insight columns) if not
-- already applied.
BEGIN;

DROP POLICY IF EXISTS "Instructors manage class grades" ON public.grades;
CREATE POLICY "Instructors manage class grades" ON public.grades
FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.answer_sheets s
    JOIN public.exams e ON e.id = s.exam_id
    JOIN public.classes c ON c.id = e.class_id
    WHERE s.id = grades.sheet_id
      AND c.instructor_id = auth.uid()
  )
)
WITH CHECK (
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
