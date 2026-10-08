# Result details and AI analysis update

For the complete table layout, announcement tables, and safe retirement of the
legacy `answers` table, see `SCHEMA_ALIGNMENT.md`.

Apply `supabase_result_details.sql` in the Supabase SQL Editor before deploying
the updated backend and Flutter app. This additive migration retains existing
scores, adds saved answer evaluations and personal feedback, and creates the
transactional `save_grade_session` RPC. Use this migration for an existing
database; do not rerun the full schema script.

The backend's `SUPABASE_KEY` must be its server-side service-role key. The app
continues to use the signed-in user's JWT and RLS. The backend checks instructor
ownership for session saving, class analysis, and release. Students can request
personal feedback only for their own released results.

## Deploying to the Hugging Face Space

The app points at `https://noelpi-checkmate-backend.hf.space` by default, so the
deployed Space must run this backend version. `hf_space/` mirrors the deployed
service: keep `main.py`, `ai_service.py`, `ai_instructions.py`, and
`result_analysis.py` in sync with `backend/` before pushing.

The Space must also be configured with the **service-role** Supabase key:

1. Supabase Dashboard → Project Settings → API → copy the `service_role` key
   (it starts with `sb_secret_`).
2. HF Space → Settings → Variables and secrets → set `SUPABASE_KEY` to that key
   (replace any `sb_publishable_...` value).

With a publishable key the grade write is blocked by Row Level Security, the old
`batch-save-grades` silently reported success with no saved count, and the app
failed with `Bad state: The full session was not saved`. The updated endpoint
fails loudly with an actionable message instead. Apply `supabase_result_details.sql`
once so the `answers`/`student_insight` columns exist.

## Short answer-sheet codes

Printed codes use `CM-` plus eight characters, such as `CM-8K9P2X8Q`.
The `answer_sheets.sheet_identifier` column stores this code as text. Database
primary keys and `grades.sheet_id` remain UUIDs; the backend resolves the printed
code to the internal key before saving the session. UUID QR payloads are no
longer supported. Re-export old sheets to register and print their short codes.

Overlay exports now select an approved assessment and use registered student
sheets instead of hard-coded sample QR values. After instructor review, each
locally graded sheet is stored as JSON on the device and synced automatically
under its own assessment ID. Sheets from different assessments and printed sets
can be scanned in any order. A failed network save stays queued with a visible
Retry sync action.
Deploy the updated backend before using the updated app, and apply
`supabase_result_details.sql` if the session RPC is not installed yet.

Old grade rows with no matching legacy item rows contain only total scores;
their missing answers cannot be recovered from those totals. New completed
scans save question
snapshots in printed set order, selected answers, correct answers, and the
phone's deterministic evaluations. No scanned images are uploaded.

Class analysis runs for one or more saved results and joins item IDs to the
`questions` table. Instructors can review one sheet or a student's course
history before release. Students can only access their own released history.
If AI generation fails, the response is marked `source: summary` and the app
offers a retry. Personal feedback is saved on the grade under the same access
rules as its score. Automatic sync does not release results; an instructor must
release them explicitly.

Verification:

```powershell
backend/venv/Scripts/python.exe -m pytest backend/tests/test_result_analysis.py -q
flutter test test/exam_results_fetch_test.dart test/student_result_fetch_test.dart test/answer_evaluation_test.dart
```

Flutter tests require the project's OpenCV native build prerequisites on the
host. The result tests use mocked AI and database services; they do not call a
live AI provider or modify Supabase.
