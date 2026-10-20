# SignLanguageTranslate

An iPad app for Indian Sign Language: download or import INCLUDE videos,
extract body and hand landmarks with Apple Vision, and train sign models
locally with MLX Swift. The target device is a 2021 iPad Pro M1 with 2 TB
storage.

**Work in progress.** Dataset management, feature extraction, training,
evaluation, and sync have implementations. End-to-end training correctness
has not been established. No recognition accuracy or device performance is
claimed. See the [code review](docs/reviews/2026-10-20-code-review.md),
[current verification results](docs/status.md), and
[completion roadmap](docs/plans/completion-roadmap.md).

## Open and build

1. Open `SignLanguageTranslate.xcodeproj` in Xcode. The latest local review
   uses Xcode 27.0; the deployment target is iOS/iPadOS 26.2 and the project
   uses Swift 5 language mode.
2. Allow Xcode to resolve the committed
   [package lockfile](SignLanguageTranslate.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).
   It pins MLX Swift 0.30.6, ZIPFoundation 0.9.20, and transitive
   swift-numerics 1.1.1. Do not substitute Python MLX APIs.
3. Select the `SignLanguageTranslate` scheme and an available iPad simulator
   to build the UI and run non-Metal tests. Use a physical iPad for MLX
   execution. Configure your own development signing team for device builds.

From the repository directory:

```bash
xcrun simctl list devices available

# Substitute an available iPad destination if necessary.
xcodebuild build -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2' \
  -quiet > /tmp/slt-build.log 2>&1
tail -40 /tmp/slt-build.log

xcodebuild test -scheme SignLanguageTranslate \
  -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (3rd generation),OS=26.2' \
  -quiet > /tmp/slt-test.log 2>&1
tail -60 /tmp/slt-test.log
```

Inspect the command exit status as well as the log. Build and test output
belongs in `/tmp`, not the repository. Simulator success does not verify
MLX training; two model initialization tests explicitly skip there.

## App workflow

The three-column navigation contains datasets, downloads, pipeline, training,
and settings. Start with INCLUDE, download its parts or import a local archive,
extract and ingest the videos, then extract Apple Vision features in the
pipeline. Training consumes those saved features rather than decoding video
during each epoch. Model testing and inference are implemented but have the
correctness gaps described in the review.

INCLUDE's manifest describes 15 categories and 44 ZIP parts. The recorded
archive total is 56,751,819,975 bytes; extraction and temporary imports need
additional space. The app's free-space allowance is an estimate, not a measured
full-pipeline requirement. The iPad's 2 TB is disk capacity, not a training
memory budget.

Video and feature files live under the app's Documents directory. SwiftData
stores metadata, relationships, and relative paths. Hugging Face and R2
credentials belong in Keychain. Cloud sync is optional to the local workflow;
the presence of a sync implementation is not evidence of a validated round trip.

## Repository guide

| Location | Purpose |
| --- | --- |
| [App source guide](docs/app/README.md) | Startup, navigation, service ownership, and storage |
| `SignLanguageTranslate/Core/` | Persistence, extensions, Keychain, and preflight utilities |
| `SignLanguageTranslate/DesignSystem/` | Shared visual tokens and components |
| `SignLanguageTranslate/Features/` | Dataset manager, extraction, analysis, training, and sync |
| [Training guide](docs/training/README.md) | Active training path, model contracts, and limitations |
| [Test guide](docs/testing/README.md) | Running tests, disabled suites, and device verification |
| [Documentation index](docs/README.md) | Review, plans, decisions, design, and historical evidence |
| `automation/` | Earlier Python orchestrator and dashboard; not used for current work |

## Contributing

Read the [project brief](CLAUDE.md), any supplied `AGENTS.md` instructions,
[decisions](docs/decisions.md), and the assigned plan before editing. The authorized current task is
[review and cleanup](docs/plans/review-cleanup.md). Keep changes small and
record their verification. Xcode uses synchronized folders: do not edit
`project.pbxproj` to register or remove source files. Do not rename the
SwiftData `Label` entity; use `SwiftUI.Label` in views.

No license file is currently provided. Review the INCLUDE dataset's own
terms separately before redistribution.
