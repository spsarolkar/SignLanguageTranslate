# Tests

Source paths below are relative to `SignLanguageTranslateTests/`.

Run the `SignLanguageTranslate` scheme from the repository root. Use
`xcrun simctl list devices available` to find an iPad destination, then:

```bash
xcodebuild test -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2' \
  -quiet -resultBundlePath /tmp/slt-tests.xcresult > /tmp/slt-test.log 2>&1
tail -60 /tmp/slt-test.log
```

Use a fresh result-bundle path for subsequent runs. For one class, add
`-only-testing:SignLanguageTranslateTests/DownloadTaskTests`.
Inspect xcodebuild's exit status; a quiet log is not proof of success.

If a run fails while collecting simulator diagnostics, preserve its failure
log and distinguish that infrastructure failure from test assertions. After
a successful build of the current sources, a full serial rerun can use:

```bash
xcodebuild test-without-building -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2' \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -quiet -resultBundlePath /tmp/slt-tests-serial.xcresult > /tmp/slt-test-serial.log 2>&1
```

This still executes the full suite; it skips compilation and verbose failure
diagnostics. Do not use it with stale build products after source changes.

## Existing coverage and gaps

Tests cover persistence models/relationships, shared utilities, manifest
generation, download queue/engine/coordinator helpers, import matching,
multipart merging, ingestion, and selected UI-facing summaries. The historical
[test plan](../../SignLanguageTranslateTests/TEST_PLAN.md) describes earlier module expectations; its planned
counts are not current execution results. Use [status](../status.md)
for measured pass/fail/skip counts.

Three entire suites are currently compiled out with `#if false`:

- `Downloads/DownloadManagerTests.swift`: stale API.
- `Downloads/DownloadProgressTrackerTests.swift`: disabled for an older
  teardown crash; the status log says the crash was subsequently fixed.
- `Persistence/PersistenceControllerTests.swift`: existing disabled suite.

They do not appear as skipped tests or contribute coverage. They were preserved
in this cleanup and need dedicated repair/re-enablement.

`DownloadIntegrationTests` creates a mock URL session, but the engine uses the
real shared background session. In particular, pause and queue-advance checks
can fail with network timing; a passing run does not resolve that design gap.
See [fix-tests](../plans/fix-tests.md).

`Models/SignLanguageModelTests.swift` checks presets and initialization. Its
two MLX model initialization tests skip on Simulator. There are no tests of
the training loop, tensor preprocessing parity, optimizer updates, checkpoint
round trips/resume, inference decoding, or callback integration.

## Physical iPad verification

Select the actual M1 iPad in Xcode and run the model tests with development
signing configured. A simulator named after an M1-era iPad does not reproduce
its Metal runtime, memory limits, background execution, or thermal behavior.

Add small deterministic fixtures before testing a full dataset: known landmark
ordering/missing points, split disjointness, finite gradients and actual weight
updates, save/load prediction equality, classification decoding, pause/resume,
and cancellation. Record the fixture, configuration, duration, memory, and
outcome. Keep dataset downloads and secrets out of unit-test fixtures.
