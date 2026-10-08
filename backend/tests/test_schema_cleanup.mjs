// Disposable PostgreSQL checks; never connects to the live Supabase project.
// Pass the same scratch-installed PGlite module path as test_notification_triggers.mjs.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const { PGlite } = await import(process.argv[2]
  ? pathToFileURL(process.argv[2]).href : '@electric-sql/pglite');
const read = (file) => readFile(new URL(`../${file}`, import.meta.url), 'utf8');
const [schema, cleanup, coreAccess, notifications, resultDetails] = await Promise.all([
  read('supabase_schema.sql'), read('supabase_schema_cleanup.sql'),
  read('supabase_core_access.sql'), read('supabase_notifications.sql'),
  read('supabase_result_details.sql'),
]);
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const teacher = id(1), alice = id(2), course = id(10), exam = id(20), sheet = id(30);
const init = `
  CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
  CREATE SCHEMA auth;
  CREATE TABLE auth.users (id uuid PRIMARY KEY, email text, raw_user_meta_data jsonb);
  CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
    'SELECT nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid';
  CREATE PUBLICATION supabase_realtime;
`;
const fixture = `
  INSERT INTO auth.users VALUES
    ('${teacher}', 'teacher@example.test', '{"name":"Instructor"}'),
    ('${alice}', 'alice@example.test', '{"name":"Alice"}');
  INSERT INTO classes (id, name, code, instructor_id)
    VALUES ('${course}', 'Course', 'TESTCODE', '${teacher}');
  INSERT INTO enrollments (class_id, user_id, role) VALUES ('${course}', '${alice}', 'Student');
  INSERT INTO exams (id, class_id, title, is_approved, total_questions, mcq_count, tf_count)
    VALUES ('${exam}', '${course}', '[Quiz] Demo', true, 10, 10, 0);
  INSERT INTO questions (exam_id, question_text, correct_answer, question_type)
    VALUES ('${exam}', 'Question text', 'A', 'MCQ');
  INSERT INTO answer_sheets (id, exam_id, student_id, sheet_identifier)
    VALUES ('${sheet}', '${exam}', '${alice}', 'CM-ABCDEFGH');
  INSERT INTO grades (sheet_id, score, total_questions, percentage, answers, student_insight)
    VALUES ('${sheet}', 8, 10, 80, '[{"answer":"A","isCorrect":true}]',
      '{"source":"summary","insight":{"strengths":["Practice is paying off"]}}');
  INSERT INTO learning_materials (class_id, title, file_name, file_type, file_size, file_url)
    VALUES ('${course}', 'Slides', 'slides.pdf', 'pdf', '1 MB', 'https://example.test/slides.pdf');
  INSERT INTO class_announcements (class_id, author_id, content)
    VALUES ('${course}', '${teacher}', 'Course update');
  INSERT INTO private_messages (class_id, student_id, sender_id, content)
    VALUES ('${course}', '${alice}', '${teacher}', 'Private update');
`;
const legacy = `
  ALTER TABLE profiles ADD COLUMN role text CHECK (role IN ('Instructor', 'Student'));
  UPDATE profiles SET role = CASE WHEN id = '${teacher}' THEN 'Instructor' ELSE 'Student' END;
  ALTER TABLE exams ADD COLUMN question_structure jsonb;
  ALTER TABLE answer_sheets ADD COLUMN status text DEFAULT 'Pending';
  ALTER TABLE answer_sheets ADD COLUMN scanned_at timestamptz;
  CREATE TABLE ai_insights (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id uuid REFERENCES exams, student_id uuid REFERENCES profiles,
    insight_text text, recommendation text, created_at timestamptz DEFAULT now());
  CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER AS $$ BEGIN
      INSERT INTO public.profiles (id, name, email, role)
      VALUES (NEW.id, NEW.raw_user_meta_data->>'name', NEW.email, 'Student');
      RETURN NEW;
    END $$;
`;

async function scalar(db, sql) {
  return Object.values((await db.query(sql)).rows[0])[0];
}
async function snapshot(db) {
  const result = {};
  for (const [table, exclude] of Object.entries({
    profiles: ['role'], classes: [], enrollments: [], exams: ['question_structure'],
    questions: [], answer_sheets: ['status', 'scanned_at'], grades: [],
    learning_materials: [], class_announcements: [], private_messages: [],
    user_notifications: [], user_notification_tokens: [],
  })) {
    const excluded = exclude.map((c) => ` - '${c}'`).join('');
    result[table] = (await db.query(`SELECT to_jsonb(t)${excluded} AS row
      FROM ${table} t ORDER BY to_jsonb(t)::text`)).rows;
  }
  return result;
}
async function assertRemoved(db) {
  assert.equal(await scalar(db, "SELECT to_regclass('public.ai_insights') IS NULL"), true);
  assert.equal(await scalar(db, `SELECT count(*)::integer FROM information_schema.columns
    WHERE table_schema = 'public' AND (
      (table_name = 'profiles' AND column_name = 'role') OR
      (table_name = 'exams' AND column_name = 'question_structure') OR
      (table_name = 'answer_sheets' AND column_name IN ('status', 'scanned_at')))`), 0);
}

const db = new PGlite();
try {
  await db.exec(init);
  await db.exec(schema);
  await assertRemoved(db);
  await db.exec(coreAccess); // Must work when the unused table is absent.
  await db.exec(notifications);
  await db.exec(resultDetails);
  await db.exec(fixture);
  await db.exec(legacy);
  await db.exec(coreAccess); // Still protects legacy AI data pending cleanup.

  // Every safety failure must leave the whole original structure and data intact.
  const guards = [
    {
      set: `INSERT INTO ai_insights (exam_id, insight_text) VALUES ('${exam}', 'Keep this legacy insight')`,
      reset: 'DELETE FROM ai_insights', error: /ai_insights contains legacy records/,
    },
    {
      set: `UPDATE exams SET question_structure = '{"items":[1]}'`,
      reset: 'UPDATE exams SET question_structure = NULL', error: /question_structure contains legacy data/,
    },
    {
      set: "UPDATE answer_sheets SET status = 'Scanned'",
      reset: "UPDATE answer_sheets SET status = 'Pending'", error: /status contains nondefault legacy data/,
    },
    {
      set: 'UPDATE answer_sheets SET scanned_at = now()',
      reset: 'UPDATE answer_sheets SET scanned_at = NULL', error: /scanned_at contains legacy data/,
    },
    {
      set: 'CREATE VIEW legacy_profile_roles AS SELECT role FROM profiles',
      reset: 'DROP VIEW legacy_profile_roles', error: /cannot drop column role/,
    },
    {
      set: `CREATE FUNCTION custom_legacy_insight() RETURNS text LANGUAGE plpgsql AS $$
        BEGIN RETURN (SELECT insight_text FROM ai_insights LIMIT 1); END $$`,
      reset: 'DROP FUNCTION custom_legacy_insight()', error: /Review functions referencing retired schema/,
    },
  ];
  for (const guard of guards) {
    await db.exec(guard.set);
    const before = await snapshot(db);
    await assert.rejects(db.exec(cleanup), guard.error);
    await db.exec('ROLLBACK');
    assert.deepEqual(await snapshot(db), before);
    assert.equal(await scalar(db, "SELECT to_regclass('public.ai_insights') IS NOT NULL"), true);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role'`), 1);
    await db.exec(guard.reset);
  }
  console.log('PASS: cleanup refuses legacy data/dependencies and rolls back all changes');

  const before = await snapshot(db);
  await db.exec(cleanup);
  await assertRemoved(db);
  assert.deepEqual(await snapshot(db), before, 'All retained rows and saved feedback must be unchanged');
  await db.exec(cleanup); // Safe deployment retry.
  await db.exec(coreAccess); // Safe to rerun earlier access setup after cleanup.
  await db.exec(notifications);
  await db.exec(resultDetails);
  await assertRemoved(db);
  assert.deepEqual(await snapshot(db), before);

  // Signup still creates a profile, with names from email or Google metadata.
  await db.exec(`INSERT INTO auth.users VALUES
    ('${id(3)}', 'google@example.test', '{"full_name":"Google User"}'),
    ('${id(4)}', 'new-student@example.test', '{}');`);
  assert.equal(await scalar(db, `SELECT name FROM profiles WHERE id = '${id(3)}'`), 'Google User');
  assert.equal(await scalar(db, `SELECT name FROM profiles WHERE id = '${id(4)}'`), 'new-student');
  assert.equal(await scalar(db, `SELECT instructor_id FROM classes WHERE id = '${course}'`), teacher);
  assert.equal(await scalar(db, `SELECT role FROM enrollments WHERE user_id = '${alice}'`), 'Student');

  await db.exec(`UPDATE exams SET results_released = true, status = 'Published' WHERE id = '${exam}'`);
  assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
    WHERE kind = 'result' AND recipient_id = '${alice}' AND exam_id = '${exam}'`), 1);
  assert.equal(await scalar(db, `SELECT count(*)::integer FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'user_notifications'`), 1);
  console.log('PASS: clean/fresh schemas, idempotency, signup, class roles, saved grades/feedback and notifications');
} finally {
  await db.close();
}
