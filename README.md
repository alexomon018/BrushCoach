# BrushCoach — personal Apple Watch brushing coach

BrushCoach is an Apple Watch–first toothbrushing coach with an iPhone companion. The shipping
experience is a reliable two-minute, six-zone guided routine. Motion analysis runs alongside it and
reports what it observed — without ever deciding whether the session counted.

## Status

| Area | State |
| --- | --- |
| Two-minute six-zone Watch pacer | Wired and working |
| iPhone companion, history, reminders, Health writing | Wired and working |
| Watch complication | Wired and working |
| Handedness fork and honest capability reporting | Wired and working |
| Real brushing time, stroke rate, position change | **Wired, thresholds unvalidated** |
| Labelled trace capture → phone inbox → export → replay CLI | Wired and working |
| Personal calibration and six-zone classification (`BrushKit`) | Built and unit-tested, **not called by either app**, gated on the separability result |

Two caveats stated plainly, because the difference matters:

- The motion analysis that now runs during a session (`ActivityDetector`, `PositionChangeDetector`,
  `LiveSessionAnalyzer`) is **calibration-free and threshold-based**. Its logic is unit-tested against
  synthetic waveforms, but its default thresholds were derived from the physics of the signal, not
  from recorded brushing. They are a hypothesis until `brush-replay --separability` has been run over
  real traces. See [Validating the thresholds](#validating-the-thresholds).
- The six-zone `PersonalCalibrationBuilder` / `PersonalZoneClassifier` remain unwired. Naming a mouth
  region from a wrist IMU is the part the published work says is unreliable, and BrushCoach does not
  currently attempt it.

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
- Handedness-aware motion analysis: real brushing time, stroke-rate nudges, and position-change
  detection when the Watch is on the brushing hand — and a plain statement that it cannot check when
  it is not.

There is no Core ML model, analytics SDK, or network client. All code is native Swift and Apple
frameworks.

## Handedness

Most people wear the Watch on the non-dominant wrist and brush with the dominant hand. When those
differ the Watch is on an arm that barely moves, and no amount of signal processing recovers a
brushing stroke that was never recorded. BrushCoach treats that as a first-class, user-visible state
rather than an edge case, because the alternative is telling someone they did not brush when they
did.

The Watch reads its own wrist through `WKInterfaceDevice.current().wristLocation`, so onboarding only
ever asks **one** question: which hand holds the brush. `HandednessProfile` resolves the two into a
`SensingCapability`:

| Capability | Meaning | What the user sees |
| --- | --- | --- |
| `available` | Watch is on the brushing hand | Brushing time and coaching |
| `wrongWrist` | Watch is on the other wrist | Pacing only, with the reason stated |
| `unknown` | Question not answered yet | A prompt to answer it |

The answer is a preference, not a one-time immutable onboarding result — some people alternate hands.
It can be changed any time under **Routine → Stroke checking**, which also shows which wrist the Watch
last reported.

## What motion analysis claims, and what it does not

`LiveSessionAnalyzer` runs beside the pacer, never driving it. The pacer stays pure wall-clock, so a
sensing failure cannot slow the session, stop it, or desynchronise the timer — it only means the
summary has less to say.

What it reports:

- **Real brushing time.** Seconds the wrist was actually moving in a brushing rhythm, as opposed to
  elapsed session time. Most people's "two minutes" includes wetting the brush, rinsing, and standing
  still.
- **Stroke rate.** Dominant oscillation of the strongest acceleration axis, in strokes per minute,
  with a throttled haptic nudge past the configured ceiling.
- **Position changes.** That the wrist moved to a new posture — deliberately *not* which mouth zone it
  moved to. This is change-point detection on the gravity vector, so there is no zone label to get
  wrong, and it sidesteps the same-side confusion the literature documents.

What it never does:

- Decide whether the session counted. `BrushSession.completedRoutine` depends only on the pacer.
- Report an inconclusive reading as zero. `SessionAnalysis.isInconclusive` and the `nil` case of
  `BrushSession.activeBrushingSeconds` exist so the summary can say "couldn't check" rather than
  "you didn't brush".
- Name a mouth zone.

## Repository layout

```text
BrushCoach.xcodeproj
├── BrushCoach/                 iPhone companion app and trace inbox
├── BrushCoachWatch/            Watch coach and capture tools
├── BrushCoachWidget/           Watch complication
├── Config/                     Info plists and App Group entitlements
└── BrushKit/
    ├── Sources/BrushKit/
    │   ├── Models/             sessions, handedness, routine day, motion samples, trace JSON
    │   ├── Pipeline/           resampler, windows, feature extraction
    │   ├── Classification/     activity detector, position change, unwired zone classifier
    │   ├── Session/            SessionClock, RoutineTimeline, LiveSessionAnalyzer
    │   └── Storage/            local session repository
    ├── Sources/BrushReplay/    offline replay and separability CLI
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

Export from **More → Motion trace inbox** on the iPhone. Each row shares as its original JSON file;
**Export all** sends every valid trace through the system share sheet. Raw traces are never uploaded —
export happens only after an explicit share action.

## Validating the thresholds

This is the step that decides whether the verification features are real. Record traces labelled
`Idle` and at least one mouth zone, export them, then:

```sh
cd BrushKit
swift run brush-replay --separability /path/to/traces/*.json
```

The report pools windows by label and prints, for each group, the median and 10th/90th-percentile
motion energy and the median stroke rate; then the **best achievable single energy threshold** and its
accuracy, how the shipped default compares, and what fraction of each group passes the rhythm gate.

Read the verdict as a distribution, not a pass/fail:

| Best accuracy | What it means |
| --- | --- |
| ≥ 90% | Strong. Ship brushing time; consider retuning the default to the reported best value. |
| 75–90% | Workable but noisy. Ship only with visible uncertainty, and record more varied traces. |
| < 75% | Weak. Do not ship a verification tier on this data; check the Watch was on the brushing hand. |

Retune by changing the defaults in `ActivityDetectorConfiguration`. Every value there is documented as
provisional for exactly this reason.

## Replay traces offline

```sh
cd BrushKit
swift run brush-replay /path/to/trace.json
```

Pass several paths to compare a batch. The command prints raw duration and sample rate, feature-window
count, first-window dominant frequency and energy, feature schema version/count, and the
`LiveSessionAnalyzer` summary for that trace — active brushing seconds, fast-stroke seconds, position
changes, longest single-position hold, and median stroke rate.

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

Because windows overlap by 50%, anything accumulating time from them must attribute the **hop**, not
the window, or twenty seconds of brushing reads as forty. `LiveSessionAnalyzer` does this and has a
test pinning it.

Feature names travel alongside values for auditability. Training/export code should pin
`FeatureVector.schemaVersion` and reject a mismatch rather than silently changing model inputs.

## Known gaps

These are open, not hidden:

- **The activity thresholds have never seen real data.** See
  [Validating the thresholds](#validating-the-thresholds). This is the top open item.
- **The six-zone classifier is still unwired.** `PersonalCalibrationBuilder` and
  `PersonalZoneClassifier` are unit-tested against synthetic signals only, and no calibration UI
  exists. Wiring them is gated on the separability result above: six-way zone classification is
  strictly harder than the two-way question, so if idle does not separate cleanly from brushing on
  real traces, zones will not either.
- **watchOS cannot do passive detection.** Continuously running a watchOS app in the background is
  not a supported use case, and borrowing a workout session in a non-workout app risks App Review
  rejection. Sessions stay user-initiated; the app uses the `self-care` background mode, which is the
  correct one here.
- **`BrushSession.period`** uses the default `RoutineDay` rather than the user's configured rollover
  hour. Call sites that matter pass the configured day explicitly, so this is latent rather than
  broken.
- **No asset catalog, app icon, privacy manifest, or StoreKit integration.** These block App Store
  submission and are tracked separately from product work.

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
