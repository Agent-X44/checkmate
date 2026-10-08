-- Additive migration to allow students to view their classmates.
-- Applied after discovering that students could only see themselves in the students list.
BEGIN;

DROP POLICY IF EXISTS "Users can view all enrollments" ON public.enrollments;
CREATE POLICY "Users can view all enrollments" ON public.enrollments
FOR SELECT TO authenticated
USING (true);

COMMIT;
