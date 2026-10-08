# Automatic sheet evaluation — 8 October 2026

At the user's request, the evaluation page no longer requires per-sheet
approval. It automatically evaluates the calibrated local detections against
the resolved assessment's answer key and writes the resulting JSON to the
per-user retry queue. Network synchronization starts independently. Continue
Scanning only closes the page; closing an already saved evaluation does not
discard it or trigger a second save.

The page is read-only. It no longer re-runs detection using editable column,
threshold, or bubble settings. Missing or invalid keys, unresolved assessment
IDs, invalid printed sets, and unexplained question-count mismatches prevent saving.
Unused printed rows are excluded only when local processing explicitly records
the matched template capacity and detects every row. Missing answers are never
padded into the result. Set B preserves the existing
question shuffle and question identities. Ambiguous marks remain flagged and
score zero. Save retries use the same evaluated snapshot; the page reports
success only after the local queue write succeeds.

Assessment content approval and instructor result release remain separate
gates. Students cannot access these pending evaluations. Raw images remain
local, and AI does not grade marks.

Validation: 18 focused service, widget, ambiguity-policy, and Set B tests pass.
The tests run against copied production sources in the isolated Flutter
harness under `.dart_tool/scanner-qa/pure`, avoiding the unavailable Windows
native OpenCV toolchain. Analysis of changed source and test files is clean.
