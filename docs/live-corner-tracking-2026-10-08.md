# Responsive corner overlay — 8 October 2026

The preview previously limited camera submissions and overlay updates independently to 100ms. Every detection repeated QR localization and full-frame candidate/hypothesis work. Missed detections retained old corners, and positions had no age limit.

The worker now follows an established frame using four small local regions. It validates the detected circles with the same physical marker geometry before using their current centers. Lost/large movements fall back to full-image acquisition. Session, image size and rotation changes discard tracking state. Native QR work is optional and limited to acquisition ambiguity or unsupported ML Kit buffers, with a separate 250ms interval.

Preview processing has a 960px longest-edge limit and never upscales the stream. The camera submits at most one frame at a time, at up to 30fps, dropping busy frames. Each completed fresh frame updates a ValueNotifier overlay subtree immediately, without a second 10fps filter or rebuilding the scanner page. No averaging or prediction introduces additional positional lag. Missing, future-dated or 250ms-old frame coordinates are cleared; a timer also removes the overlay if responses stop arriving.

Full-resolution still capture, QR identity verification and deterministic OMR grading retain their independent alignment path. No raw images leave the device.

Validation: 62 pure Flutter regressions passed (including new pan, zoom, tilt, lost-marker, incorrect-bubble and stale-frame cases); changed-source analysis is clean. Android native regression runner additionally includes movement checks on both production artworks and reports timings. These native/runtime checks could not be executed here: no Android device is connected and the Windows C++ test toolchain is unavailable. Release build verifies Android compilation; actual camera latency still needs device verification.
