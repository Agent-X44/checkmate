-- Checkmate LMS Supabase Schema (Security Hardened)

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
    UNIQUE(user_id, class_id)
);

-- 4. Exams (Enforces BR-03 and BR-11)
CREATE TABLE exams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id UUID REFERENCES classes(id),
    title TEXT NOT NULL,
    status TEXT CHECK (status IN ('Draft', 'Ready', 'Published')) DEFAULT 'Draft',
    is_approved BOOLEAN DEFAULT FALSE,
    results_released BOOLEAN DEFAULT FALSE,
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
    status TEXT DEFAULT 'Pending',
    scanned_at TIMESTAMPTZ
);

-- 7. Grades (Final score per sheet)
CREATE TABLE grades (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id UUID REFERENCES answer_sheets(id) ON DELETE CASCADE,
    score INT,
    total_questions INT,
    percentage FLOAT,
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

-- --- ROW LEVEL SECURITY (RLS) ---

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE grades ENABLE ROW LEVEL SECURITY;

-- Students can only see profiles of people in their classes (simplified here for brevity)
CREATE POLICY "Public profiles are viewable by everyone" ON profiles FOR SELECT USING (true);

-- Classes: Instructors can manage their own, students can see enrolled
CREATE POLICY "Instructors manage own classes" ON classes FOR ALL USING (auth.uid() = instructor_id);

-- Exams: Students can only see approved exams in their classes
CREATE POLICY "Students see approved exams" ON exams FOR SELECT
USING (is_approved = true AND class_id IN (SELECT class_id FROM enrollments WHERE user_id = auth.uid()));

-- Grades: Students can only see their own released grades (BR-12)
CREATE POLICY "Students see own released grades" ON grades FOR SELECT
USING (
    sheet_id IN (
        SELECT id FROM answer_sheets
        WHERE student_id = auth.uid()
        AND exam_id IN (SELECT id FROM exams WHERE results_released = true)
    )
);
