// Isolated PostgreSQL regression checks; never connects to the Supabase project.
// npm install --prefix <scratch-directory> --ignore-scripts @electric-sql/pglite
// node backend/tests/test_notification_triggers.mjs <scratch-directory>/node_modules/@electric-sql/pglite/dist/index.js
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const { PGlite } = await import(process.argv[2]
  ? pathToFileURL(process.argv[2]).href
  : '@electric-sql/pglite');
const migration = await readFile(new URL('../supabase_notifications.sql', import.meta.url), 'utf8');
const repair = await readFile(new URL('../supabase_notification_release_fix.sql', import.meta.url), 'utf8');
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`;
const teacher = id(1), alice = id(2), bob = id(3), outsider = id(4);
const course = id(10), exam = id(20), quiz = id(21), legacyExam = id(22);
const material = id(30), legacyMaterial = id(31);
const aliceSheet = id(40), bobSheet = id(41), quizSheet = id(42);
const outsiderSheet = id(43), duplicateSheet = id(44), legacySheet = id(45);

const fixture = `
  CREATE ROLE anon;
  CREATE ROLE authenticated;
  CREATE SCHEMA auth;
  CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
    'SELECT nullif(current_setting(''request.jwt.claim.sub'', true), '''')::uuid';
  CREATE TABLE profiles (id uuid PRIMARY KEY, name text);
  CREATE TABLE classes (id uuid PRIMARY KEY, name text, instructor_id uuid REFERENCES profiles);
  CREATE TABLE enrollments (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    class_id uuid REFERENCES classes, user_id uuid REFERENCES profiles, role text);
  CREATE TABLE exams (id uuid PRIMARY KEY, class_id uuid REFERENCES classes,
    title text, results_released boolean DEFAULT false);
  CREATE TABLE answer_sheets (id uuid PRIMARY KEY, exam_id uuid REFERENCES exams,
    student_id uuid REFERENCES profiles);
  -- Deliberately model the older deployed grades table without answers JSONB.
  CREATE TABLE grades (id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    sheet_id uuid REFERENCES answer_sheets, score integer, percentage double precision);
  CREATE TABLE learning_materials (id uuid PRIMARY KEY, class_id uuid REFERENCES classes,
    title text, file_name text, file_url text);
  GRANT USAGE ON SCHEMA auth TO authenticated;
  GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
  CREATE PUBLICATION supabase_realtime;
  INSERT INTO profiles VALUES
    ('${teacher}', 'Instructor'), ('${alice}', 'Alice'), ('${bob}', 'Bob'), ('${outsider}', 'Former student');
  INSERT INTO classes VALUES ('${course}', 'CheckMate class', '${teacher}');
  INSERT INTO enrollments (class_id, user_id, role) VALUES
    ('${course}', '${teacher}', 'Instructor'), ('${course}', '${alice}', 'Student'),
    ('${course}', '${bob}', 'Student');
  INSERT INTO exams (id, class_id, title, results_released) VALUES
    ('${exam}', '${course}', 'Exam', false), ('${quiz}', '${course}', 'Quiz', false),
    ('${legacyExam}', '${course}', 'Previously released exam', true);
  INSERT INTO answer_sheets VALUES
    ('${aliceSheet}', '${exam}', '${alice}'), ('${bobSheet}', '${exam}', '${bob}'),
    ('${quizSheet}', '${quiz}', '${bob}'), ('${outsiderSheet}', '${exam}', '${outsider}'),
    ('${duplicateSheet}', '${exam}', '${alice}'), ('${legacySheet}', '${legacyExam}', '${alice}');
  INSERT INTO grades (sheet_id, score, percentage) VALUES
    ('${aliceSheet}', 8, 80), ('${duplicateSheet}', 9, 90), ('${outsiderSheet}', 7, 70),
    ('${legacySheet}', 6, 60);
  INSERT INTO learning_materials VALUES
    ('${legacyMaterial}', '${course}', 'Existing slides', 'old.pdf', 'https://example.test/old.pdf');
`;

async function scalar(db, sql) {
  return Object.values((await db.query(sql)).rows[0])[0];
}

async function visible(db, user, where = 'true') {
  await db.exec(`SET ROLE authenticated; SET request.jwt.claim.sub = '${user}';`);
  try {
    return await scalar(db, `SELECT count(*)::integer FROM user_notifications WHERE ${where}`);
  } finally {
    await db.exec('RESET ROLE; RESET request.jwt.claim.sub;');
  }
}

for (const mode of ['full migration', 'existing installation repair']) {
  const db = new PGlite();
  try {
    await db.exec(fixture);
    await db.exec(migration);
    if (mode === 'existing installation repair') {
      // Simulate an older working announcement/message setup with no materials.
      await db.exec(`
        DROP TRIGGER learning_material_notification ON learning_materials;
        DROP TRIGGER learning_material_notification_update ON learning_materials;
        DROP TRIGGER learning_material_notification_delete ON learning_materials;
        DROP TRIGGER late_released_grade_notification ON grades;
        ALTER TABLE user_notifications DROP CONSTRAINT user_notifications_kind_check;
        ALTER TABLE user_notifications ADD CONSTRAINT user_notifications_kind_check
          CHECK (kind IN ('announcement', 'message', 'result'));
        DROP POLICY "Recipients read notifications" ON user_notifications;
        CREATE POLICY "Recipients read notifications" ON user_notifications FOR SELECT
          TO authenticated USING (recipient_id = auth.uid() AND kind <> 'module_upload');
        DROP TRIGGER released_result_notification ON exams;
        CREATE TRIGGER released_result_notification AFTER UPDATE OF results_released
          ON exams FOR EACH ROW
          WHEN (NEW.results_released IS TRUE AND OLD.results_released IS DISTINCT FROM TRUE)
          EXECUTE FUNCTION notify_released_result();
      `);
      await db.exec(repair);
      await db.exec(repair); // Deployment retries must be harmless.
    } else {
      await db.exec(migration);
    }
    assert.equal(await scalar(db, 'SELECT count(*)::integer FROM user_notifications'), 0,
      'Installing the migration must not send historical notifications');
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = 'user_notifications'`), 1);

    await db.exec(`INSERT INTO learning_materials VALUES
      ('${material}', '${course}', 'Week 2 slides', 'week2.pdf', 'https://example.test/week2.pdf')`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE kind = 'module_upload' AND source_id = '${material}'`), 2);
    assert.equal(await visible(db, alice, "kind = 'module_upload'"), 1);
    assert.equal(await visible(db, outsider), 0);
    assert.equal(await visible(db, teacher), 0);
    await db.exec(`UPDATE learning_materials SET title = 'Updated slides' WHERE id = '${material}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE kind = 'module_upload' AND source_id = '${material}' AND body = 'Updated slides'`), 2);
    await db.exec(`UPDATE learning_materials SET title = title WHERE id = '${legacyMaterial}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE kind = 'module_upload' AND source_id = '${legacyMaterial}'`), 2,
      'A material retry must recover missing notifications');

    assert.equal(await scalar(db, "SELECT count(*)::integer FROM user_notifications WHERE kind = 'result'"), 0,
      'Saved grades must stay silent before explicit release');
    await db.exec(`UPDATE exams SET results_released = true WHERE id = '${exam}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE kind = 'result' AND exam_id = '${exam}'`), 1,
      'Only enrolled students with saved grades receive results, once per assessment');
    assert.equal(await visible(db, alice, "kind = 'result'"), 1);
    assert.equal(await visible(db, bob, "kind = 'result'"), 0);
    assert.equal(await visible(db, bob, `recipient_id = '${alice}'`), 0);

    const noticeId = await scalar(db, `SELECT id FROM user_notifications
      WHERE kind = 'result' AND exam_id = '${exam}'`);
    await db.exec(`UPDATE user_notifications SET read_at = now() WHERE id = '${noticeId}';
      UPDATE exams SET results_released = true WHERE id = '${exam}';`);
    assert.equal(await scalar(db, `SELECT id FROM user_notifications
      WHERE kind = 'result' AND exam_id = '${exam}'`), noticeId);
    assert.equal(await scalar(db, `SELECT read_at IS NOT NULL FROM user_notifications WHERE id = '${noticeId}'`), true);

    await db.exec(`INSERT INTO grades (sheet_id, score, percentage) VALUES ('${bobSheet}', 7, 70)`);
    assert.equal(await visible(db, bob, "kind = 'result'"), 1,
      'A reviewed grade synced after release must notify its owner');
    await db.exec(`DELETE FROM user_notifications WHERE kind = 'result' AND recipient_id = '${bob}';
      UPDATE grades SET percentage = 71 WHERE sheet_id = '${bobSheet}';`);
    assert.equal(await visible(db, bob, "kind = 'result'"), 1,
      'A persisted percentage update must also recover missing notices');
    await db.exec(`UPDATE exams SET results_released = true WHERE id = '${legacyExam}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE kind = 'result' AND exam_id = '${legacyExam}'`), 1,
      'Releasing an already released exam must recover its missing notice');

    await db.exec(`UPDATE exams SET results_released = true WHERE id = '${quiz}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE exam_id = '${quiz}'`), 0, 'Unsynced quiz grades must not produce result notices');
    await db.exec(`INSERT INTO grades (sheet_id, score, percentage) VALUES ('${quizSheet}', 5, 50)`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE exam_id = '${quiz}'`), 1, 'Quiz releases follow the same saved-grade gate');
    await db.exec(`UPDATE exams SET results_released = false WHERE id = '${exam}'`);
    assert.equal(await visible(db, alice, `exam_id = '${exam}'`), 0,
      'Unreleased results must be hidden from students');
    await db.exec(`UPDATE exams SET results_released = true WHERE id = '${exam}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE exam_id = '${exam}'`), 2, 'Another release must preserve the original notices');

    // The shared user_notifications INSERT path is what feeds Realtime and FCM.
    await db.exec(`INSERT INTO class_announcements (class_id, author_id, content)
      VALUES ('${course}', '${teacher}', 'Announcement still works');
      INSERT INTO private_messages (class_id, student_id, sender_id, content)
      VALUES ('${course}', '${alice}', '${teacher}', 'Message still works');`);
    assert.equal(await visible(db, alice, "kind = 'announcement'"), 1);
    assert.equal(await visible(db, alice, "kind = 'message'"), 1);
    await db.exec(`DELETE FROM learning_materials WHERE id = '${material}'`);
    assert.equal(await scalar(db, `SELECT count(*)::integer FROM user_notifications
      WHERE source_id = '${material}'`), 0, 'Deleting a material must remove its notices');
    console.log(`PASS: ${mode} — materials, exams, quizzes, retries, late sync, privacy and existing notifications`);
  } finally {
    await db.close();
  }
}
