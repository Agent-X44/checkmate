-- Run once in the Supabase SQL Editor. Safe to rerun after a failed attempt.
-- Includes the course announcement tables if the earlier migration was skipped.
-- Existing core tables (profiles, classes, enrollments, exams, sheets, grades)
-- must already be present.
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
          WHERE c.id = class_announcements.class_id
            AND c.instructor_id = auth.uid())
  OR EXISTS (SELECT 1 FROM public.enrollments e
             WHERE e.class_id = class_announcements.class_id
               AND e.user_id = auth.uid() AND e.role = 'Student')
);

DROP POLICY IF EXISTS "Instructor creates announcements" ON public.class_announcements;
CREATE POLICY "Instructor creates announcements" ON public.class_announcements
FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (SELECT 1 FROM public.classes c
              WHERE c.id = class_announcements.class_id
                AND c.instructor_id = auth.uid())
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

CREATE TABLE IF NOT EXISTS public.private_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL CHECK (length(btrim(content)) BETWEEN 1 AND 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  edited_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS private_messages_conversation_idx
  ON public.private_messages (class_id, student_id, created_at);

CREATE TABLE IF NOT EXISTS public.user_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('announcement', 'message', 'module_upload', 'result')),
  source_id UUID NOT NULL,
  class_id UUID REFERENCES public.classes(id) ON DELETE CASCADE,
  exam_id UUID REFERENCES public.exams(id) ON DELETE CASCADE,
  related_student_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ,
  UNIQUE (recipient_id, kind, source_id)
);
CREATE INDEX IF NOT EXISTS user_notifications_recipient_created_idx
  ON public.user_notifications (recipient_id, created_at DESC);

ALTER TABLE public.user_notifications
  DROP CONSTRAINT IF EXISTS user_notifications_kind_check;
ALTER TABLE public.user_notifications
  ADD CONSTRAINT user_notifications_kind_check
  CHECK (kind IN ('announcement', 'message', 'module_upload', 'result'));

CREATE TABLE IF NOT EXISTS public.user_notification_tokens (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK (platform = 'android'),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, token)
);

ALTER TABLE public.private_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_notification_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.private_messages, public.user_notifications FROM anon, authenticated;
REVOKE ALL ON public.user_notification_tokens FROM anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.private_messages TO authenticated;
GRANT UPDATE (content, edited_at) ON public.private_messages TO authenticated;
GRANT SELECT ON public.user_notifications TO authenticated;
GRANT UPDATE (read_at) ON public.user_notifications TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_notification_tokens TO authenticated;

DROP POLICY IF EXISTS "Conversation participants read messages" ON public.private_messages;
CREATE POLICY "Conversation participants read messages" ON public.private_messages
FOR SELECT TO authenticated USING (
  (student_id = auth.uid() OR EXISTS (
    SELECT 1 FROM public.classes c
    WHERE c.id = class_id AND c.instructor_id = auth.uid()))
  AND EXISTS (
    SELECT 1 FROM public.enrollments e
    WHERE e.class_id = private_messages.class_id
      AND e.user_id = private_messages.student_id AND e.role = 'Student')
);

DROP POLICY IF EXISTS "Conversation participants send messages" ON public.private_messages;
CREATE POLICY "Conversation participants send messages" ON public.private_messages
FOR INSERT TO authenticated WITH CHECK (
  sender_id = auth.uid()
  AND (sender_id = student_id OR EXISTS (
    SELECT 1 FROM public.classes c
    WHERE c.id = class_id AND c.instructor_id = sender_id))
  AND EXISTS (
    SELECT 1 FROM public.enrollments e
    WHERE e.class_id = private_messages.class_id
      AND e.user_id = private_messages.student_id AND e.role = 'Student')
);

DROP POLICY IF EXISTS "Senders edit messages" ON public.private_messages;
CREATE POLICY "Senders edit messages" ON public.private_messages
FOR UPDATE TO authenticated USING (sender_id = auth.uid())
WITH CHECK (sender_id = auth.uid());
DROP POLICY IF EXISTS "Senders delete messages" ON public.private_messages;
CREATE POLICY "Senders delete messages" ON public.private_messages
FOR DELETE TO authenticated USING (sender_id = auth.uid());

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

DROP POLICY IF EXISTS "Users manage their own notification tokens" ON public.user_notification_tokens;
CREATE POLICY "Users manage their own notification tokens"
ON public.user_notification_tokens
FOR ALL TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "Recipients mark notifications read" ON public.user_notifications;
CREATE POLICY "Recipients mark notifications read" ON public.user_notifications
FOR UPDATE TO authenticated USING (recipient_id = auth.uid())
WITH CHECK (recipient_id = auth.uid());

CREATE OR REPLACE FUNCTION public.notify_class_announcement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_notifications
    (recipient_id, kind, source_id, class_id, title, body)
  SELECT DISTINCT e.user_id, 'announcement', NEW.id, NEW.class_id,
    'New announcement in ' || c.name, left(NEW.content, 180)
  FROM public.enrollments e
  JOIN public.classes c ON c.id = e.class_id
  WHERE e.class_id = NEW.class_id AND e.role = 'Student'
    AND e.user_id IS NOT NULL AND e.user_id <> NEW.author_id
  ON CONFLICT (recipient_id, kind, source_id) DO NOTHING;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS class_announcement_notification ON public.class_announcements;
CREATE TRIGGER class_announcement_notification AFTER INSERT ON public.class_announcements
FOR EACH ROW EXECUTE FUNCTION public.notify_class_announcement();

CREATE OR REPLACE FUNCTION public.sync_announcement_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.user_notifications
    WHERE kind = 'announcement' AND source_id = OLD.id;
    RETURN OLD;
  END IF;
  UPDATE public.user_notifications SET body = left(NEW.content, 180)
  WHERE kind = 'announcement' AND source_id = NEW.id;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS class_announcement_notification_update ON public.class_announcements;
CREATE TRIGGER class_announcement_notification_update
AFTER UPDATE OF content ON public.class_announcements FOR EACH ROW
EXECUTE FUNCTION public.sync_announcement_notification();
DROP TRIGGER IF EXISTS class_announcement_notification_delete ON public.class_announcements;
CREATE TRIGGER class_announcement_notification_delete
AFTER DELETE ON public.class_announcements FOR EACH ROW
EXECUTE FUNCTION public.sync_announcement_notification();

CREATE OR REPLACE FUNCTION public.notify_private_message()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE recipient UUID;
DECLARE sender_name TEXT;
BEGIN
  IF NEW.sender_id <> NEW.student_id THEN
    recipient := NEW.student_id;
  END IF;
  SELECT p.name INTO sender_name FROM public.profiles p WHERE p.id = NEW.sender_id;
  IF recipient IS NOT NULL AND recipient <> NEW.sender_id THEN
    INSERT INTO public.user_notifications
      (recipient_id, kind, source_id, class_id, related_student_id, title, body)
    VALUES (recipient, 'message', NEW.id, NEW.class_id, NEW.student_id,
      'Message from ' || coalesce(sender_name, 'a class member'),
      left(NEW.content, 180))
    ON CONFLICT (recipient_id, kind, source_id) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS private_message_notification ON public.private_messages;
CREATE TRIGGER private_message_notification AFTER INSERT ON public.private_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_private_message();

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

CREATE OR REPLACE FUNCTION public.sync_private_message_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.user_notifications
    WHERE kind = 'message' AND source_id = OLD.id;
    RETURN OLD;
  END IF;
  UPDATE public.user_notifications SET body = left(NEW.content, 180)
  WHERE kind = 'message' AND source_id = NEW.id;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS private_message_notification_update ON public.private_messages;
CREATE TRIGGER private_message_notification_update
AFTER UPDATE OF content ON public.private_messages FOR EACH ROW
EXECUTE FUNCTION public.sync_private_message_notification();
DROP TRIGGER IF EXISTS private_message_notification_delete ON public.private_messages;
CREATE TRIGGER private_message_notification_delete
AFTER DELETE ON public.private_messages FOR EACH ROW
EXECUTE FUNCTION public.sync_private_message_notification();

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

-- If a reviewed sheet finishes syncing after release, notify its student too.
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
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
    AND NOT EXISTS (SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public'
      AND tablename = 'private_messages') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.private_messages;
  END IF;
END $$;

COMMIT;
