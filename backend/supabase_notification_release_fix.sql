-- For an existing database where message/announcement notifications work.
-- Run in the Supabase SQL Editor. Safe to rerun; does not resend old notices.
-- For a new notification installation, use supabase_notifications.sql instead.
BEGIN;

ALTER TABLE public.user_notifications
  DROP CONSTRAINT IF EXISTS user_notifications_kind_check;
ALTER TABLE public.user_notifications
  ADD CONSTRAINT user_notifications_kind_check
  CHECK (kind IN ('announcement', 'message', 'module_upload', 'result'));

-- Older inbox policies did not permit module_upload. Keep the result release
-- and ownership checks for both the inbox and Realtime local notifications.
DROP POLICY IF EXISTS "Recipients read notifications" ON public.user_notifications;
CREATE POLICY "Recipients read notifications" ON public.user_notifications
FOR SELECT TO authenticated USING (
  recipient_id = auth.uid()
  AND (
    (kind = 'result' AND EXISTS (
      SELECT 1 FROM public.exams x
      JOIN public.answer_sheets s ON s.exam_id = x.id
      JOIN public.grades g ON g.sheet_id = s.id
      WHERE x.id = user_notifications.exam_id
        AND x.results_released = TRUE AND s.student_id = auth.uid()))
    OR (kind IN ('announcement', 'message', 'module_upload') AND (
      EXISTS (SELECT 1 FROM public.classes c WHERE c.id = user_notifications.class_id
        AND c.instructor_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.enrollments e
        WHERE e.class_id = user_notifications.class_id
          AND e.user_id = auth.uid() AND e.role = 'Student')))
  )
);

CREATE OR REPLACE FUNCTION public.notify_learning_material_upload()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_notifications
    (recipient_id, kind, source_id, class_id, title, body)
  SELECT DISTINCT e.user_id, 'module_upload', NEW.id, NEW.class_id,
    'New learning material in ' || c.name,
    left(coalesce(nullif(btrim(NEW.title), ''), NEW.file_name, 'A new material is available.'), 180)
  FROM public.enrollments e
  JOIN public.classes c ON c.id = e.class_id
  WHERE e.class_id = NEW.class_id AND e.role = 'Student'
    AND e.user_id IS NOT NULL
  ON CONFLICT (recipient_id, kind, source_id) DO NOTHING;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS learning_material_notification ON public.learning_materials;
CREATE TRIGGER learning_material_notification
AFTER INSERT OR UPDATE OF title, file_name, file_url ON public.learning_materials
FOR EACH ROW
EXECUTE FUNCTION public.notify_learning_material_upload();

CREATE OR REPLACE FUNCTION public.sync_learning_material_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.user_notifications
    WHERE kind = 'module_upload' AND source_id = OLD.id;
    RETURN OLD;
  END IF;
  UPDATE public.user_notifications
  SET body = left(coalesce(nullif(btrim(NEW.title), ''), NEW.file_name, 'A new material is available.'), 180)
  WHERE kind = 'module_upload' AND source_id = NEW.id;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS learning_material_notification_update ON public.learning_materials;
CREATE TRIGGER learning_material_notification_update
AFTER UPDATE OF title, file_name ON public.learning_materials FOR EACH ROW
EXECUTE FUNCTION public.sync_learning_material_notification();
DROP TRIGGER IF EXISTS learning_material_notification_delete ON public.learning_materials;
CREATE TRIGGER learning_material_notification_delete
AFTER DELETE ON public.learning_materials FOR EACH ROW
EXECUTE FUNCTION public.sync_learning_material_notification();

CREATE OR REPLACE FUNCTION public.notify_released_result()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_notifications
    (recipient_id, kind, source_id, class_id, exam_id, title, body)
  SELECT DISTINCT s.student_id, 'result', NEW.id, NEW.class_id, NEW.id,
    'Results released: ' || NEW.title,
    'Your score is ready. Open for personal AI analysis.'
  FROM public.answer_sheets s
  JOIN public.grades g ON g.sheet_id = s.id
  JOIN public.enrollments e ON e.class_id = NEW.class_id
    AND e.user_id = s.student_id AND e.role = 'Student'
  WHERE s.exam_id = NEW.id AND s.student_id IS NOT NULL
  ON CONFLICT (recipient_id, kind, source_id) DO NOTHING;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS released_result_notification ON public.exams;
CREATE TRIGGER released_result_notification
AFTER UPDATE OF results_released ON public.exams FOR EACH ROW
-- Repeating a release repairs missing notices; the unique key prevents duplicates.
WHEN (NEW.results_released IS TRUE)
EXECUTE FUNCTION public.notify_released_result();

CREATE OR REPLACE FUNCTION public.notify_late_released_grade()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE released_exam RECORD;
BEGIN
  SELECT x.id, x.class_id, x.title, s.student_id INTO released_exam
  FROM public.answer_sheets s JOIN public.exams x ON x.id = s.exam_id
  JOIN public.enrollments e ON e.class_id = x.class_id
    AND e.user_id = s.student_id AND e.role = 'Student'
  WHERE s.id = NEW.sheet_id AND x.results_released = TRUE
    AND s.student_id IS NOT NULL;
  IF FOUND THEN
    INSERT INTO public.user_notifications
      (recipient_id, kind, source_id, class_id, exam_id, title, body)
    VALUES (released_exam.student_id, 'result', released_exam.id,
      released_exam.class_id, released_exam.id,
      'Results released: ' || released_exam.title,
      'Your score is ready. Open for personal AI analysis.')
    ON CONFLICT (recipient_id, kind, source_id) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS late_released_grade_notification ON public.grades;
CREATE TRIGGER late_released_grade_notification
-- Older grade tables have no answers column. Any persisted grade update can
-- repair a missing notice without depending on the result-detail migration.
AFTER INSERT OR UPDATE ON public.grades
FOR EACH ROW EXECUTE FUNCTION public.notify_late_released_grade();

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
    AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'user_notifications') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_notifications;
  END IF;
END $$;

COMMIT;
