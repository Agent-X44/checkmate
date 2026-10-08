# Assessment management changes

Instructors long-press a draft quiz/exam to enter selection mode, tap other drafts to select them, and use the bottom action bar to select all (up to 100 per request), cancel, or delete after confirmation. Back cancels selection without leaving the page; navigation is blocked while deletion is running. There is no top-right selection/deletion button. Approved and released assessments cannot be selected. The backend validates instructor ownership and draft status for every ID before making changes. Drafts with generated answer sheets are protected, including assessments returned to Draft that already have saved grades. Questions are removed by the existing database cascade in a single deletion query. Concurrently approved/released IDs are excluded and the app reports the IDs actually deleted.

The assessment menu exposes **Unrelease results** and **Unapprove / return to draft**. Unrelease is also available on the results and class insights pages. Unrelease keeps approval and saved results; students lose access through the existing release checks and RLS policies. Unapproval sets approval and release to false together, returns status to Draft, and blocks new sheet generation. Existing sheets, grades, and insights remain stored. The instructor can approve and release again.

Approval, unapproval, release, unrelease, and deletion require authentication and class instructor ownership. Client fallbacks that could bypass backend rejection of approval or deletion were removed. Release requires current approval. Assessment lists refresh on returning from results; results refresh on returning from class insights.

## Validation

- 64 offline backend tests passed across assessment management, result analysis, and sheet identification/synchronization.
- Flutter analysis of the five changed client files passed without issues.
- Android arm64 release APK built successfully.

## Deployment

Deploy the updated `backend/main.py` alongside the updated app. The app uses the new `/delete-draft-exams` and `/unrelease-results/{exam_id}` routes. Existing schema cascades and release-aware RLS are used; this change does not require a new SQL migration. Withdrawal governs subsequent access and does not erase results already viewed or copied by students.
