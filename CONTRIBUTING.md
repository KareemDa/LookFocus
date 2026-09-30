# Contributing

This is an experimental personal project. Small, scoped fixes with an explanation and relevant tests are welcome. Keep camera processing local, avoid recording frames, and preserve explicit pause and input holds.

Run `swift test` and `swift build -c release` on macOS. Include actual hardware/software details and distinguish observed behavior from automated-test results. Do not include private photographs, window names, calibration exports, signing material, tokens, or credentials in issues or commits.

The optional photograph integration test is local-only and is skipped without its two environment inputs. Improvements should include synthetic/core regression cases where possible.
