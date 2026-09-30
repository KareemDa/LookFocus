# Verification

- Clean `swift test`:34 tests, zero failures, one optional local-photo test skipped without image inputs.
- Clean release compilation passed on macOS26 with Swift6.3.
- The initial 0.5.0 configurable signing script completed a local build and strict signature verification using a persistent Keychain identity. No signing material or binary is included in the repository.
- Source review and path/credential scanning found no personal image, calibration export, private signing key, embedded Git credential, or machine-specific path in the publication files.

Tests prove the covered decision rules, not webcam accuracy or guaranteed switching latency. No controlled battery-runtime result or quiet-session idle stop/resume result is claimed.

## 0.5.1

- Battery saver now defaults to enabled when the preference is absent, preserving an explicitly saved choice.
- Tests: 34 executed, one optional photo test skipped, zero failures. Release compilation passed.
- The first signing attempts failed locally. Signing with the same persistent identity and an explicit login Keychain succeeded, followed by strict signature verification before and after installation.
- Real settings screenshots confirm Battery saver is enabled, the live indicator remains disabled, and the camera is off while the selected work monitor is absent. Screenshots were captured from the installed 0.5.1 app.
- The poster is a generated illustration, not evidence of live tracking accuracy.
