# Cached updates and prepared AI feedback

Confirmed create/join operations update the course drawer and dashboard through a shared account-scoped cache. Reopening those screens first loads the device snapshot and refreshes it in the background. Concurrent course loads share a single request; a response started before a confirmed mutation cannot erase that mutation. Successful draft creation, approval, unapproval, release, and withdrawal update assessment metadata directly without waiting for another complete list fetch. Deletions update the shared cache and cannot be undone by older fetches.

Learning material uploads retain their progress card while storage and database writes complete. The returned record is then inserted into the cached list immediately; it stays visible until the ordered server stream acknowledges it. Failed storage writes are reported as failures. Cached downloaded files use account and material IDs to avoid filename collisions across courses and accounts. All device snapshot keys are scoped to the signed-in user; old shared-account keys are ignored. Reads and events return copies, and disk writes are serialized per key.

AI analysis is prepared after the transactional grade save succeeds, and released personal history is prepared after release. Opening an instructor's assessment list also warms existing saved results. A short debounce merges scans of the same assessment. Personal feedback is persisted in grades.student_insight; class and history analysis use a bounded cache encrypted on the backend disk with a key derived from its existing server credential. Two AI calls run at once, and concurrent requests for the same data share one job. Background database I/O uses worker threads.

Cache versions depend on saved grades and relevant question context. Changed results produce a new version. Personal feedback writes compare the saved score, item answers, and total in the database update, preventing an older AI response from attaching to a replaced evaluation. AI responses are cached for one day; deterministic fallback summaries have a short retry interval. Class analysis can be explicitly refreshed. Permissions and release state are checked before cached data is returned and again after lengthy generation. Students cannot access unreleased feedback; AI never grades marks or receives scanned images.

Backend disk caches may be cleared when the hosting container is rebuilt; prepared personal feedback remains in Supabase, and other feedback is regenerated from saved results. A first analysis can still take time when a result was just saved or its cache is absent.

## Verification and delivery

- 142 offline backend tests passed, including deduplication, bounded concurrency, encrypted persistence, invalidation, background preparation, and release/access gates.
- 9 Flutter cache tests passed against copied production sources in the isolated Flutter harness, including account switching, concurrent mutations, stale responses, persistence, and deep copies. The root Windows test hook requires the unavailable native OpenCV toolchain; the isolated cache tests do not change the app's native setup.
- Flutter analysis of all 11 changed client files passed.
- Android arm64 release APK built successfully.
- Backend revision ffc6c9bf553802e9ebb21c91d580b7a0e9ce7482 deployed to the configured Hugging Face Space. No new SQL migration or secret is required.
