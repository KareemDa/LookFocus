# Verification for the initial public snapshot

- Clean `swift test`:34 tests, zero failures, one optional local-photo test skipped without image inputs.
- Clean release compilation passed on macOS26 with Swift6.3.
- The local signing script accepts an identity supplied by the builder. Signing validation of this publication copy did not complete in this session; the local signing check was stopped. No signing material or binary is included in the repository.
- Source review and path/credential scanning found no personal image, calibration export, private signing key, embedded Git credential, or machine-specific path in the publication files.

Tests prove the covered decision rules, not webcam accuracy or guaranteed switching latency. No controlled battery-runtime result or quiet-session idle stop/resume result is claimed.
