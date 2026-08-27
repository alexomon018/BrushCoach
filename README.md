# BrushCoach — personal Apple Watch brushing coach

BrushCoach is an Apple Watch–first toothbrushing coach with an iPhone companion. The shipping
experience is a reliable two-minute, six-zone guided routine. A separate motion-classification
library and labelled-data capture harness exist alongside it as developer tools; they are **not**
part of the user-facing session yet.

## Status

| Area | State |
| --- | --- |
| Two-minute six-zone Watch pacer | Wired and working |
| iPhone companion, history, reminders, Health writing | Wired and working |
| Watch complication | Wired and working |
| Labelled trace capture → phone inbox → export → replay CLI | Wired and working |
| Motion pipeline and feature extraction (`BrushKit`) | Built and unit-tested, **not called by either app** |
| Personal calibration and zone classification (`BrushKit`) | Built and unit-tested, **not called by either app**, never validated against real traces |

A live brushing session currently reads **no** motion data. `SessionEngine`, `MotionPipeline`,
`PersonalCalibrationBuilder`, `PersonalZoneClassifier`, and `PredictionSmoother` have no callers
outside `BrushKit` and its tests. `BrushSession.verifiedZones` is therefore always `nil`.

## What works today

- A wall-clock-based two-minute Watch session with six 20-second zones, wrist-down extended runtime
  under the `self-care` background mode, and a transition haptic at each zone change.
- Pause, resume, and an end-early path that keeps credit for the zones already brushed.
- A WidgetKit Watch complication in circular, corner, inline, and rectangular families that opens
  directly into a session.
- A companion iPhone experience for morning/evening status, local history, editing, deletion,
  reminder times, and optional floss/tongue prompts.
- Reminder scheduling that omits a morning or evening period once a matching session arrives from
  the Watch.
- Opt-in Apple Health writing using the toothbrushing event category, including update and deletion
  by BrushCoach session ID.
- ADA-aligned onboarding and coaching language: two minutes twice daily, fluoride toothpaste, soft
  bristles, gentle pressure, and an approximately 45-degree gumline angle.

Routine credit depends only on the pacer. It is never withheld because motion analysis failed, and
`verifiedZones` is deliberately distinct from `zonesCompleted` so that a future verification layer
cannot retroactively take credit away.

There is no Core ML model, analytics SDK, or network client. All code is native Swift and Apple
frameworks.

## What is included

- `BrushCoachWatch`: the guided six-zone session, plus a developer trace-capture screen reached from
  **More → Developer → Motion capture** on the ready screen.
- `BrushCoach`: the consumer iPhone app (Today, History, Routine, More), and a trace inbox that
  validates incoming JSON, stores it locally, shows measured duration/sample rate, and exports one or
  many traces through the system share sheet.
- `BrushCoachWidget`: the Watch complication.
- `BrushKit`: a shared Swift package containing the session model and storage, the pure `SessionClock`
  and `RoutineTimeline` that drive the pacer, the stable trace schema, the motion pipeline, and the
  (currently unwired) personal calibration classifier and `SessionEngine`.
- `brush-replay`: a macOS Swift CLI that sends exported traces through `MotionPipeline` and
  `SessionEngine` without a watch.
- `BrushKitTests`: deterministic tests for wall-clock session timing, routine-day and streak logic,
  session persistence and schema migration, timestamp resampling, spectral feature extraction,
  overlapping windows, personal calibration/classification, smoothing, fixture decoding, and replay.

## Repository layout

```text
BrushCoach.xcodeproj
├── BrushCoach/                 iPhone companion app and trace inbox
├── BrushCoachWatch/            Watch coach and capture tools
├── BrushCoachWidget/           Watch complication
├── Config/                     Info plists and App Group entitlements
└── BrushKit/
    ├── Sources/BrushKit/
    │   ├── Models/             sessions, routine day, motion samples, labelled trace JSON
    │   ├── Pipeline/           resampler, windows, feature extraction
    │   ├── Classification/     personal profile, classifier, and pacer fallback (unwired)
    │   ├── Session/            SessionClock, RoutineTimeline, SessionEngine
    │   └── Storage/            local session repository
    ├── Sources/BrushReplay/    offline replay CLI
    └── Tests/BrushKitTests/    unit tests and trace fixture
```

## One-time Xcode setup

Requirements: Swift 6, Xcode 16 or newer, iOS 18+, and watchOS 11+.

1. Open `BrushCoach.xcodeproj`.
2. Select the `BrushCoach` target, open **Signing & Capabilities**, and select your team.
3. Repeat for `BrushCoachWatch`.
4. For a paid-team Release build, create or enable the App Group `group.com.aleksamitic.BrushCoach`
   for both targets. Debug builds under a free Personal Team use each app's private Application
   Support directory instead.
5. If you use different bundle identifiers, change the App Group consistently in:
   - both files under `Config/*.entitlements`
   - `PhoneTraceStore.appGroupIdentifier`
   - `WatchTraceStore.appGroupIdentifier`
   - the iOS/watch target bundle identifiers and `WKCompanionAppBundleIdentifier`
6. Run the iPhone app once, then run the watch app on its paired watch.

The watch and iPhone have separate filesystems even when they use the same App Group identifier. The
watch writes into its local container first; WatchConnectivity transfers the completed file; the
iPhone validates and writes that file into its own local container. The Debug configuration
intentionally omits the App Group entitlement so it can be signed by a free Personal Team. Release
retains the entitlement files for paid-team provisioning.

## Developer labelled-data capture

No dataset has been collected yet. The checked-in `short-trace.json` fixture exists to prove the JSON
round-trips through the pipeline; it is not training data.

From the Watch ready screen, open **More → Developer → Motion capture**:

1. Tap **Choose label** and select one of the six coarse mouth zones, `Transition`, or `Idle`.
2. Set the wrist that is wearing the watch. For useful brushing traces, the watch must be on the
   brushing hand.
3. Tap **Record 10 seconds**.
4. Use the three-second countdown to place the brush. Move naturally for the full capture; do not
   chase the screen.
5. Wait for the success haptic. The JSON file is saved before it is queued for transfer, so a
   temporarily unreachable phone does not discard the recording.

Build a balanced dataset. Record every zone in multiple sessions and on multiple days. Include
deliberate `Idle` traces and natural `Transition` traces. Vary stance, brush, tempo, and mirror
position; otherwise a model can learn the recording setup instead of brushing motion.

The requested rate is 50 Hz, but every Core Motion sample retains its real monotonic timestamp. The
iPhone inbox and replay CLI report the actual measured rate so dropouts are visible.

## Export from iPhone

Open the iPhone app after captures transfer and go to **More → Motion trace inbox**. Each row can be
shared as its original JSON file. **Export all** sends every valid trace to Files, AirDrop, or another
destination through the system share sheet.

Raw traces are never uploaded by BrushCoach. Export happens only after an explicit share action.

## Replay traces offline

From the repository root:

```sh
cd BrushKit
swift run brush-replay /path/to/trace.json
```

Pass several paths to compare a batch:

```sh
swift run brush-replay /path/to/trace-1.json /path/to/trace-2.json
```

The command prints raw duration and sample rate, feature-window count, first-window dominant frequency
and energy, feature schema version/count, and `SessionEngine` event totals.

## Run tests

```sh
cd BrushKit
swift test
```

## Pipeline contract

`MotionPipeline` performs these steps in order:

1. Interpolate irregular timestamped samples onto a fixed 50 Hz grid. No stage assumes uniform
   incoming `dt`.
2. Form 2-second (100-sample) windows with a 1-second hop, giving 50% overlap.
3. Emit feature schema version 1 with a stable 91-value order:
   - mean, standard deviation, RMS, minimum, and maximum for each axis of user acceleration, rotation
     rate, gravity, and jerk;
   - magnitude statistics for acceleration, rotation, gravity, and jerk;
   - dominant acceleration frequency, spectral energy, and zero-crossing rate;
   - mean and variance for each attitude-quaternion component.

The spectral calculation is a deterministic, dependency-free DFT. It uses the acceleration axis with
the highest variance so a symmetric back-and-forth stroke is not incorrectly frequency-doubled by
taking an absolute magnitude first.

Feature names travel alongside values for auditability. Training/export code should pin
`FeatureVector.schemaVersion` and reject a mismatch rather than silently changing model inputs.

## Known gaps

These are open, not hidden:

- **The classifier has never seen real data.** `PersonalCalibrationBuilder` and
  `PersonalZoneClassifier` are unit-tested against synthetic signals only. Their accuracy on real
  brushing is unknown, and published wrist-IMU work suggests coarse zones are the realistic ceiling.
- **Consumer onboarding never asks about handedness.** Most people wear the watch on the
  non-dominant hand and brush with the dominant one; if those differ, wrist IMU data is largely
  useless for zone inference. `WatchWrist` currently appears only on the developer capture screen, so
  `PersonalCalibrationProfile.watchWrist` has no consumer path that populates it. This has to become a
  first-class onboarding question before any verification layer ships.
- **`CalibrationProfileStore` is unreferenced.** It persists a profile that nothing currently
  produces or consumes.
- **watchOS cannot do passive detection.** Continuously running a watchOS app in the background is
  not a supported use case, and borrowing a workout session in a non-workout app risks App Review
  rejection. Sessions must stay user-initiated. The app uses the `self-care` background mode, which
  is the correct one here.
- **`BrushSession.period`** uses the default `RoutineDay` rather than the user's configured rollover
  hour. Call sites that matter pass the configured day explicitly, so this is latent rather than
  broken.

## JSON and privacy

Each trace contains:

- schema version, UUID, ISO-8601 recording date, label, requested rate/duration, and optional
  wrist/notes;
- timestamp, user acceleration, rotation rate, gravity, and attitude quaternion for every sample.

Everything is on-device and local. There are no third-party packages, analytics SDKs, or network
calls. Do not commit personal exported traces to source control unless you explicitly intend to
contribute them.

## Scope

BrushCoach supports a routine. It does not assess dental health, does not measure surface coverage,
and does not replace advice from a dental professional.
