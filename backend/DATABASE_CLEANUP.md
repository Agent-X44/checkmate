# CheckMate database cleanup

The cleanup removes one obsolete table and four columns confirmed unused by
the current app/backend. Existing users, classes, enrollments, assessments,
questions, answer sheets, grades, messages, materials, and notifications stay.

| Removed object | Reason |
| --- | --- |
| `ai_insights` | No current reads or writes. Personal feedback is stored in `grades.student_insight`; class analysis uses saved grades and returns its analysis through FastAPI. |
| `profiles.role` | A user can teach one course and join another. Roles belong to `classes.instructor_id` and `enrollments.role`; a global account role was overwritten by creating/joining courses. |
| `exams.question_structure` | No current reader or writer. Questions and active sheet-template metadata already define the assessment. |
| `answer_sheets.status` | The app never maintained this field, leaving graded sheets labelled `Pending`. A saved grade is the evidence that a reviewed sheet synced. |
| `answer_sheets.scanned_at` | No current reader or writer. Saved grades retain their existing timestamps. |

The other 14 tables in the screenshots support implemented features. Keep
`announcement_comments` and `learning_materials` even when empty. Invitation
tokens secure joining; the notification inbox and Android device tokens serve
different parts of notification delivery. Keep `grades.answers` and
`grades.student_insight` for item results and personal feedback. Keep exam
approval/release flags, status, question counts, template, and printed-set
fields: the app uses them for approval, scanning, printing, and result access.

No test/demo records are selected for deletion. Similar profile names or
emails, draft exams, repeated question text, and pending sheets do not establish
that the rows are disposable.

## Apply to the existing database

1. Deploy the updated `backend/main.py` and install the updated Flutter app
   first. Their old `ai_insights` deletion calls and global profile-role writes
   have been removed. The updated code also works before the cleanup runs.
2. Run `supabase_schema_cleanup.sql` in the Supabase SQL Editor. Use this
   migration for the existing project; `supabase_schema.sql` is for fresh
   databases only.
3. Verify profile creation, creating/joining courses, student result access,
   and material/result notifications. No Firebase or webhook changes are needed.

The migration replaces the signup function before dropping the global role.
It runs in one transaction and locks the affected tables while checking data.
It refuses to drop a nonempty `ai_insights` table, nonempty question structure,
nondefault sheet status, or nonnull scan time. It also checks explicit legacy
references in public database functions and uses `RESTRICT` for catalog
dependencies. An error rolls back the entire cleanup; review the named data or
dependency before changing the migration. It never uses `CASCADE` to force
removals. Custom dynamic SQL references cannot be detected exhaustively.

The script is safe to rerun and reloads the database API schema cache after a
successful cleanup. Earlier core-access and notification migrations remain
compatible with the reduced schema.

Read-only verification:

```sql
SELECT to_regclass('public.ai_insights') AS obsolete_insight_table;

SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND (
  (table_name = 'profiles' AND column_name = 'role') OR
  (table_name = 'exams' AND column_name = 'question_structure') OR
  (table_name = 'answer_sheets' AND column_name IN ('status', 'scanned_at'))
);
```

The first query should return null and the second should return no rows.

## Verification in an isolated database

These tests do not connect to or mutate the Supabase project. The SQL test
checks a fresh schema, cleanup of an older schema, preservation of retained
rows, signup, class roles, notifications, retries, and rollback on legacy data
or custom dependencies. From the project root in PowerShell:

```powershell
npm.cmd install --prefix "$env:TEMP\checkmate-notification-sql-tests" --no-audit --no-fund --ignore-scripts @electric-sql/pglite
node backend/tests/test_schema_cleanup.mjs "$env:TEMP\checkmate-notification-sql-tests\node_modules\@electric-sql\pglite\dist\index.js"
backend/venv/Scripts/python.exe -m pytest backend/tests/test_schema_cleanup_compatibility.py backend/tests/test_result_analysis.py backend/tests/test_notification_delivery.py -q
dart analyze lib/services/supabase_service.dart
```
