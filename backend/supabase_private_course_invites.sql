BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

DROP TRIGGER IF EXISTS refresh_course_invitation_expiry ON public.classes;
DROP FUNCTION IF EXISTS public.refresh_course_invitation_expiry();
DROP POLICY IF EXISTS "Users manage own enrollments" ON public.enrollments;
ALTER TABLE public.classes DROP COLUMN IF EXISTS invite_expires_at;

CREATE TABLE IF NOT EXISTS public.course_invitation_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.course_invitation_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.course_invitation_tokens FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.issue_course_invitation(p_class_id UUID)
RETURNS TABLE(invite_token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    raw_token TEXT := replace(gen_random_uuid()::TEXT || gen_random_uuid()::TEXT, '-', '');
    token_expiry TIMESTAMPTZ := NOW() + INTERVAL '7 days';
BEGIN
    IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.classes
        WHERE id = p_class_id AND instructor_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Course owner access required';
    END IF;

    INSERT INTO public.course_invitation_tokens (class_id, token_hash, expires_at)
    VALUES (
        p_class_id,
        encode(digest(convert_to(raw_token, 'UTF8'), 'sha256'), 'hex'),
        token_expiry
    );

    RETURN QUERY SELECT raw_token, token_expiry;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_course_invitation_valid(p_token TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
    SELECT p_token ~ '^[A-Fa-f0-9]{64}$'
       AND EXISTS (
           SELECT 1
           FROM public.course_invitation_tokens t
           WHERE t.token_hash = encode(digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
             AND t.revoked_at IS NULL
             AND t.expires_at > NOW()
       );
$$;

CREATE OR REPLACE FUNCTION public.join_course_with_invitation(p_token TEXT)
RETURNS TABLE(id UUID, name TEXT, instructor_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    target_class UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT t.class_id INTO target_class
    FROM public.course_invitation_tokens t
    WHERE p_token ~ '^[A-Fa-f0-9]{64}$'
      AND t.token_hash = encode(digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
      AND t.revoked_at IS NULL
      AND t.expires_at > NOW()
    LIMIT 1;

    IF target_class IS NULL THEN
        RAISE EXCEPTION 'Invitation link is invalid, expired, or revoked';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.classes
        WHERE classes.id = target_class AND classes.instructor_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Course owners cannot join their own course';
    END IF;

    INSERT INTO public.enrollments (user_id, class_id, role)
    VALUES (auth.uid(), target_class, 'Student')
    ON CONFLICT (user_id, class_id) DO NOTHING;

    RETURN QUERY
    SELECT c.id, c.name, c.instructor_id
    FROM public.classes c
    WHERE c.id = target_class;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_course_with_code(p_code TEXT)
RETURNS TABLE(id UUID, name TEXT, instructor_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_class UUID;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT c.id INTO target_class
    FROM public.classes c
    WHERE upper(c.code) = upper(regexp_replace(trim(p_code), '[^A-Za-z0-9]', '', 'g'))
    LIMIT 1;

    IF target_class IS NULL THEN
        RAISE EXCEPTION 'Invalid course code';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.classes
        WHERE classes.id = target_class AND classes.instructor_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Course owners cannot join their own course';
    END IF;

    INSERT INTO public.enrollments (user_id, class_id, role)
    VALUES (auth.uid(), target_class, 'Student')
    ON CONFLICT (user_id, class_id) DO NOTHING;

    RETURN QUERY
    SELECT c.id, c.name, c.instructor_id
    FROM public.classes c
    WHERE c.id = target_class;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_owned_course_code(p_class_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    course_code TEXT;
BEGIN
    SELECT c.code INTO course_code
    FROM public.classes c
    WHERE c.id = p_class_id AND c.instructor_id = auth.uid();
    IF course_code IS NULL THEN
        RAISE EXCEPTION 'Course owner access required';
    END IF;
    RETURN course_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.reset_owned_course_code(p_class_id UUID, p_new_code TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.classes
        WHERE id = p_class_id AND instructor_id = auth.uid()
    ) THEN
        RAISE EXCEPTION 'Course owner access required';
    END IF;
    IF p_new_code !~ '^[A-Z0-9]{5,8}$' THEN
        RAISE EXCEPTION 'Invalid course code format';
    END IF;

    UPDATE public.classes SET code = p_new_code WHERE id = p_class_id;
    UPDATE public.course_invitation_tokens
    SET revoked_at = NOW()
    WHERE class_id = p_class_id AND revoked_at IS NULL;

    RETURN p_new_code;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_course_invitation(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_course_invitation_valid(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_course_with_invitation(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.join_course_with_code(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_owned_course_code(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reset_owned_course_code(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.issue_course_invitation(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_course_invitation_valid(TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.join_course_with_invitation(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_course_with_code(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_owned_course_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reset_owned_course_code(UUID, TEXT) TO authenticated;

REVOKE SELECT ON TABLE public.classes FROM PUBLIC, anon, authenticated;
GRANT SELECT (id, name, instructor_id, created_at)
    ON TABLE public.classes TO authenticated;
REVOKE INSERT ON TABLE public.classes FROM PUBLIC, anon, authenticated;
GRANT INSERT (id, name, code, instructor_id, created_at)
    ON TABLE public.classes TO authenticated;
REVOKE UPDATE ON TABLE public.classes FROM PUBLIC, anon, authenticated;
REVOKE SELECT (code) ON TABLE public.classes FROM PUBLIC, anon, authenticated;
REVOKE UPDATE (code) ON TABLE public.classes FROM PUBLIC, anon, authenticated;
GRANT UPDATE (name) ON TABLE public.classes TO authenticated;
REVOKE INSERT ON TABLE public.enrollments FROM PUBLIC, anon, authenticated;
REVOKE UPDATE ON TABLE public.enrollments FROM PUBLIC, anon, authenticated;

CREATE POLICY "Users manage own enrollments" ON public.enrollments
FOR ALL TO authenticated
USING (
    auth.uid() = user_id
    OR class_id IN (
        SELECT id FROM public.classes WHERE instructor_id = auth.uid()
    )
)
WITH CHECK (
    auth.uid() = user_id
    AND class_id IS NOT NULL
);

COMMIT;
