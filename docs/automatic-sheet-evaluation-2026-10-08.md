# Automatic sheet evaluation — 8 October 2026

> **Superseded on 9 October 2026:** saving is no longer automatic. The page
> grades the capture as an unsaved draft. Only **Confirm & Continue** writes it
> to the retry queue (BR-07: queue after instructor review). Retake, or going
> back without confirming, discards the draft. That leaves a blurry or
> misaligned capture out of the results, and the same paper can be scanned
> again. A failed queue write stays on the page, and Confirm retries the same
> result. The rest of this note still applies.

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
