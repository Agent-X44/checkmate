# Draft saving correction — 8 October 2026

A read-only query of the deployed database confirmed that exams.template_id is absent (42703), while total_questions, mcq_count, tf_count and has_multiple_sets are available. Both client and backend were inserting the missing column.

Draft saving now uses the authenticated instructor backend route. The backend retries only a missing-template-column error and only if the supplied template matches the template derived from question counts. These counts are persisted, and existing sheet/scanner code derives the registered template from question types. Other database errors are not silently ignored. Current schemas still retain template_id.

Each generated draft gets a stable UUID retained for retries. A repeated completed request returns the same assessment after comparing its class, title, set configuration and question content/key. Failed question inserts remove the incomplete exam. Drafts remain unapproved. No migration or live test assessment was created.

The generation screen now reports actual save state, keeps questions available for retry/export, warns before discarding an unsaved completed draft and does not show a saved return action until success. The review transition no longer layers two scrolling question lists. Raw server/client diagnostics are logged rather than displayed in the banner.

Validation: backend regression suite, Flutter analysis of changed files and Android ARM64 release build. The app update is required because draft requests now carry authentication and retry identifiers.

Deployment: Hugging Face revision 433a92f6ef8790657f4851f2bc641f818f34d1c9 verified RUNNING, health online/database connected, new draft retry schema visible and unauthenticated draft creation rejected with 401. All 150 backend tests passed.
