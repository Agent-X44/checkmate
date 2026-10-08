# Android push notifications

## Repair missing material and result notifications

If messages and announcements already produce phone alerts, run
`supabase_notification_release_fix.sql` in the Supabase SQL Editor. It updates
the existing notification setup without changing Firebase credentials or the
working message/announcement triggers. The Android app already handles
`module_upload` and `result` through the same foreground local-notification
and background FCM paths.

The repair allows material notifications through the student inbox policy,
installs the material triggers, and creates result notifications only for
currently enrolled students with a persisted grade. A grade saved after an
assessment is released also creates its student's notice. Repeated releases
and material updates can repair missing notices while preserving existing
notification IDs and read status. The grade trigger works with older tables
that do not yet have `grades.answers`; that column previously caused the full
notification migration to fail and roll back on those installations.

The script does not send notifications for historical uploads or releases
automatically. To recover a specific missed event, replace the UUID in one of
these statements after applying the repair:

```sql
-- Recover a material's missing notices without uploading the file again.
UPDATE public.learning_materials SET title = title
WHERE id = '<material UUID>';

-- Recover an already released exam/quiz. This cannot release a draft result.
UPDATE public.exams SET results_released = results_released
WHERE id = '<exam or quiz UUID>' AND results_released IS TRUE;
```

Newly inserted `user_notifications` rows drive both Realtime local alerts and
the existing INSERT webhook for Android background alerts. Existing notices
are not inserted again. Test with a student enrolled in the affected class:
upload a new material, then explicitly release an assessment with a synced
grade. Check the in-app inbox and phone alerts with the app open and then in
the background. No new Android build or backend deployment is required for
this database repair if messages and announcements already work using the
current notification service.

This read-only query verifies that the triggers are installed and enabled
(`tgenabled` should be `O`):

```sql
SELECT tgname, tgenabled, pg_get_triggerdef(oid)
FROM pg_trigger
WHERE NOT tgisinternal AND tgname IN (
  'learning_material_notification',
  'released_result_notification',
  'late_released_grade_notification'
)
ORDER BY tgname;
```

## First-time setup

1. Run `supabase_notifications.sql` in the Supabase SQL Editor. The migration adds the `module_upload` event, a user-scoped Android device-token table, and triggers for newly uploaded learning materials.
2. In Firebase Console, register the Android app with package name `com.checkmate.checkmate`, download `google-services.json`, and place it at `android/app/google-services.json`. The Android Gradle plugin is applied only when this file exists, so Firebase configuration is optional for local development.
3. Set these secrets in the FastAPI deployment environment:
   Hugging Face Spaces rejects underscores in secret names. Enter these names without underscores there; the backend accepts both forms. For local `.env` files, keep the usual underscored names:
   - `SUPABASEURL` (`SUPABASE_URL`)
   - `SUPABASESERVICEROLEKEY` (`SUPABASE_SERVICE_ROLE_KEY`; server-side only, never put it in Flutter)
   - `SUPABASENOTIFICATIONWEBHOOKSECRET` (`SUPABASE_NOTIFICATION_WEBHOOK_SECRET`; a long random value)
   - `FIREBASESERVICEACCOUNTJSON` (`FIREBASE_SERVICE_ACCOUNT_JSON`; Firebase service-account JSON serialized as one environment-variable value)
   - `SUPABASEKEY` (`SUPABASE_KEY`; existing Supabase anon/publishable key if the backend needs it)
4. In Supabase Database Webhooks, create an `INSERT` webhook for `public.user_notifications`, targeting `https://<backend-host>/webhooks/user-notifications`. Add the header `X-CheckMate-Webhook-Secret` with the same value as `SUPABASENOTIFICATIONWEBHOOKSECRET`. Use the standard webhook payload containing `type`, `schema`, `table`, and `record`.
5. Build and install the configured Android app. It asks for notification permission after sign-in. Supabase Realtime drives foreground local notifications; FCM delivers while the app is backgrounded or closed. Notifications are persisted in Supabase and remain available in the in-app feed if permission is denied or push delivery is unavailable.

FastAPI checks that class notifications target a current Student enrollment before sending. Firebase server credentials are loaded only by the backend. Invalid FCM tokens are removed; transient send errors are logged and returned to the webhook sender. The persisted notification remains available in the in-app feed if push delivery fails. Local/foreground display and tap handling use the persisted notification ID and do not include result scores in the push payload.

## Isolated SQL regression checks

The regression test runs the full migration and the repair in disposable
PostgreSQL databases via PGlite. It covers older grade schemas, material
uploads/edits/deletion, exam and quiz releases, late grade sync, notification
retries, student visibility, and the existing messages/announcements. It never
connects to the configured Supabase project. From the project root in PowerShell:

```powershell
npm.cmd install --prefix "$env:TEMP\checkmate-notification-sql-tests" --no-audit --no-fund --ignore-scripts @electric-sql/pglite
node backend/tests/test_notification_triggers.mjs "$env:TEMP\checkmate-notification-sql-tests\node_modules\@electric-sql\pglite\dist\index.js"
```
