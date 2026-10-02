-- Fresh-database starting schema. For an existing project, run the additive
-- migrations in SCHEMA_ALIGNMENT.md instead of rerunning this file.
BEGIN;

-- 1. Profiles (Linked to auth.users)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    role TEXT CHECK (role IN ('Instructor', 'Student')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger to create profile on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, name, email, role)
  VALUES (new.id, new.raw_user_meta_data->>'name', new.email, 'Student'); -- Default to student
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- 2. Classes
CREATE TABLE classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    instructor_id UUID REFERENCES profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Enrollments (Enforces BR-01)
CREATE TABLE enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id),
    class_id UUID REFERENCES classes(id),
    role TEXT CHECK (role IN ('Instructor', 'Student')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, class_id)
);

-- 4. Exams (Enforces BR-03 and BR-11)
CREATE TABLE exams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES classes(id),
    title TEXT NOT NULL,
    status TEXT CHECK (status IN ('Draft', 'Ready', 'Published')) DEFAULT 'Draft',
    is_approved BOOLEAN DEFAULT FALSE,
    has_multiple_sets BOOLEAN DEFAULT FALSE,
    results_released BOOLEAN DEFAULT FALSE,
    template_id TEXT DEFAULT 'standard_50_questions',
    total_questions INT DEFAULT 0,
    mcq_count INT DEFAULT 0,
    tf_count INT DEFAULT 0,
    question_structure JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Questions
CREATE TABLE questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id UUID REFERENCES exams(id) ON DELETE CASCADE,
    question_text TEXT NOT NULL,
    question_type TEXT DEFAULT 'MCQ',
    correct_answer TEXT NOT NULL,
    topic_tag TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Answer Sheets (Unique per student per exam - BR-04/05)
CREATE TABLE answer_sheets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id UUID REFERENCES exams(id),
    student_id UUID REFERENCES profiles(id),
    sheet_identifier TEXT UNIQUE NOT NULL,
    set_type TEXT NOT NULL DEFAULT '1' CHECK (set_type IN ('1', '2', 'A', 'B')),
    status TEXT DEFAULT 'Pending',
    scanned_at TIMESTAMPTZ
);
-- 7. Grades (score and itemized local OMR evaluations per sheet)
CREATE TABLE grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id UUID REFERENCES answer_sheets(id) ON DELETE CASCADE,
    score INT,
    total_questions INT,
    percentage FLOAT,
    answers JSONB NOT NULL DEFAULT '[]'::jsonb,
    student_insight JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. AI Insights (Enforces BR-09 and BR-10)
CREATE TABLE ai_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id UUID REFERENCES exams(id),
    student_id UUID REFERENCES profiles(id), -- Null for class-wide insights
    insight_text TEXT,
    recommendation TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Learning Materials (BR-01)
CREATE TABLE learning_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES classes(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    file_name TEXT NOT NULL,
    file_type TEXT NOT NULL,
    file_size TEXT NOT NULL,
    file_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Course announcements and class comments (Course Stream in the UML)
CREATE TABLE class_announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES profiles(id),
    content TEXT NOT NULL CHECK (length(btrim(content)) > 0),
    allow_comments BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);
CREATE INDEX class_announcements_class_created_idx
    ON class_announcements (class_id, created_at DESC);

CREATE TABLE announcement_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    announcement_id UUID NOT NULL REFERENCES class_announcements(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES profiles(id),
    content TEXT NOT NULL CHECK (length(btrim(content)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX announcement_comments_post_created_idx
    ON announcement_comments (announcement_id, created_at);

-- --- ROW LEVEL SECURITY (RLS) ---

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE grades ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;
ALTER TABLE learning_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE announcement_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "View learning materials" ON learning_materials FOR SELECT
USING (
  class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid()) OR
  class_id IN (SELECT class_id FROM enrollments WHERE user_id = auth.uid())
);

CREATE POLICY "Instructors manage materials" ON learning_materials FOR ALL
USING (
  class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid())
);

-- Students can only see profiles of people in their classes (simplified here for brevity)
CREATE POLICY "Public profiles are viewable by everyone" ON profiles FOR SELECT USING (true);

-- Classes RLS Policies
CREATE POLICY "Instructors manage own classes" ON classes FOR ALL TO authenticated
USING (auth.uid() = instructor_id)
WITH CHECK (auth.uid() = instructor_id);

CREATE POLICY "Users can view classes to join or if enrolled" ON classes FOR SELECT TO authenticated
USING (true);

-- Enrollments RLS Policies
ALTER TABLE enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE answer_sheets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own enrollments" ON enrollments FOR ALL TO authenticated
USING (auth.uid() = user_id OR class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid()))
WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view all enrollments" ON enrollments FOR SELECT TO authenticated
USING (true);

-- Instructors create and manage sheets for students in their classes.
CREATE POLICY "Instructors manage answer sheets" ON answer_sheets FOR ALL TO authenticated
USING (
  exam_id IN (
    SELECT id FROM exams
    WHERE class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid())
  )
)
WITH CHECK (
  exam_id IN (
    SELECT id FROM exams
    WHERE class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid())
  )
);

-- Students can resolve their own sheet metadata while scanning/reviewing.
CREATE POLICY "Students view own answer sheets" ON answer_sheets FOR SELECT TO authenticated
USING (student_id = auth.uid());

-- Exams RLS Policies
-- Instructors can insert exams into their own classes
CREATE POLICY "Instructors insert exams" ON exams FOR INSERT TO authenticated
WITH CHECK (class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid()));

CREATE POLICY "Instructors view own exams" ON exams FOR SELECT TO authenticated
USING (class_id IN (SELECT id FROM classes WHERE instructor_id = auth.uid()));

CREATE POLICY "Students see approved exams" ON exams FOR SELECT
USING (is_approved = true AND class_id IN (SELECT class_id FROM enrollments WHERE user_id = auth.uid()));

-- Service Role Policy (Required for backend inserting)
CREATE POLICY "Service Role Full Access" ON exams FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Service Role Full Access on questions" ON questions FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Grades: Students can only see their own released grades (BR-12)
CREATE POLICY "Students see own released grades" ON grades FOR SELECT
USING (
    sheet_id IN (
        SELECT id FROM answer_sheets
        WHERE student_id = auth.uid()
        AND exam_id IN (SELECT id FROM exams WHERE results_released = true)
    )
);

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

-- The answer key is restricted to the course owner. Students receive their
-- own item evaluations through released grades, never from questions directly.
CREATE POLICY "Instructors manage own questions" ON questions
FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM exams e JOIN classes c ON c.id = e.class_id
  WHERE e.id = questions.exam_id AND c.instructor_id = auth.uid()
))
WITH CHECK (EXISTS (
  SELECT 1 FROM exams e JOIN classes c ON c.id = e.class_id
  WHERE e.id = questions.exam_id AND c.instructor_id = auth.uid()
));

CREATE POLICY "Instructors manage own AI insights" ON ai_insights
FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM exams e JOIN classes c ON c.id = e.class_id
  WHERE e.id = ai_insights.exam_id AND c.instructor_id = auth.uid()
))
WITH CHECK (EXISTS (
  SELECT 1 FROM exams e JOIN classes c ON c.id = e.class_id
  WHERE e.id = ai_insights.exam_id AND c.instructor_id = auth.uid()
));

CREATE POLICY "Students read own released AI insights" ON ai_insights
FOR SELECT TO authenticated
USING (student_id = auth.uid() AND EXISTS (
  SELECT 1 FROM exams e
  WHERE e.id = ai_insights.exam_id AND e.results_released = TRUE
));

CREATE POLICY "Class members read announcements" ON class_announcements
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM classes c
          WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
  OR EXISTS (SELECT 1 FROM enrollments e
             WHERE e.class_id = class_announcements.class_id AND e.user_id = auth.uid()
               AND e.role = 'Student')
);
CREATE POLICY "Instructor creates announcements" ON class_announcements
FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (SELECT 1 FROM classes c
              WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
);
CREATE POLICY "Instructor updates announcements" ON class_announcements
FOR UPDATE TO authenticated
USING (author_id = auth.uid() AND EXISTS (
  SELECT 1 FROM classes c
  WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid()))
WITH CHECK (author_id = auth.uid() AND EXISTS (
  SELECT 1 FROM classes c
  WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid()));
CREATE POLICY "Instructor deletes announcements" ON class_announcements
FOR DELETE TO authenticated USING (
  author_id = auth.uid() AND EXISTS (
    SELECT 1 FROM classes c
    WHERE c.id = class_announcements.class_id AND c.instructor_id = auth.uid())
);
CREATE POLICY "Class members read announcement comments" ON announcement_comments
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM class_announcements a WHERE a.id = announcement_comments.announcement_id)
);
CREATE POLICY "Class members add enabled comments" ON announcement_comments
FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM class_announcements a
    WHERE a.id = announcement_comments.announcement_id AND a.allow_comments
      AND (EXISTS (SELECT 1 FROM classes c
                   WHERE c.id = a.class_id AND c.instructor_id = auth.uid())
           OR EXISTS (SELECT 1 FROM enrollments e
                      WHERE e.class_id = a.class_id
                        AND e.user_id = auth.uid() AND e.role = 'Student'))
  )
);

COMMIT;
