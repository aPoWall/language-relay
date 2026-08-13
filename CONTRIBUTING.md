# Contributing

Small, focused pull requests are welcome.

1. Keep runtime conversion local and free of telemetry.
2. Preserve clean-modifier semantics: modified Option and Shift sequences must never trigger.
3. Run `make test` and `git diff --check`.
4. Keep live keyboard/focus testing in the explicit `make live-integration-test` lane.
5. Add a changelog entry for visible behavior changes.

The UI follows the square, monochrome Shaper grammar. Avoid rounded pills, gradients, and decorative color.
