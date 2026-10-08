-- Apply this migration in the Supabase SQL Editor.
-- It enables instructors to create sheets for exams in their own classes.

ALTER TABLE public.exams
  ADD COLUMN IF NOT EXISTS has_multiple_sets BOOLEAN DEFAULT FALSE;

ALTER TABLE public.answer_sheets
  ADD COLUMN IF NOT EXISTS set_type TEXT NOT NULL DEFAULT 'A';

UPDATE public.answer_sheets
SET set_type = '1'
WHERE set_type IS NULL;

ALTER TABLE public.answer_sheets
  DROP CONSTRAINT IF EXISTS answer_sheets_set_type_check;

ALTER TABLE public.answer_sheets
  ADD CONSTRAINT answer_sheets_set_type_check
  CHECK (set_type IN ('1', '2', 'A', 'B'));

ALTER TABLE public.answer_sheets ENABLE ROW LEVEL SECURITY;

-- The answer-sheet policy checks the related exam. Instructors must be
-- allowed to see their own exams for that policy subquery to succeed.
DROP POLICY IF EXISTS "Instructors view own exams" ON public.exams;
CREATE POLICY "Instructors view own exams"
ON public.exams
FOR SELECT
TO authenticated
USING (
  class_id IN (
    SELECT id FROM public.classes WHERE instructor_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Instructors manage answer sheets" ON public.answer_sheets;
CREATE POLICY "Instructors manage answer sheets"
ON public.answer_sheets
FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.exams e
    JOIN public.classes c ON c.id = e.class_id
    WHERE e.id = answer_sheets.exam_id
      AND c.instructor_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.exams e
    JOIN public.classes c ON c.id = e.class_id
    WHERE e.id = answer_sheets.exam_id
      AND c.instructor_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "Students view own answer sheets" ON public.answer_sheets;
CREATE POLICY "Students view own answer sheets"
ON public.answer_sheets
FOR SELECT
TO authenticated
USING (student_id = auth.uid());
