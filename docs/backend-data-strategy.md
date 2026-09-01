# Backend and data strategy

Status: accepted; Phase 1 implemented

## Decision

BrushCoach does not need a custom REST backend for its first useful release.

Keep the app local-first:

- Store routine preferences on-device.
- Store completed sessions on-device in a schema that can evolve safely.
- Continue writing the supported toothbrushing event to HealthKit only after the user grants permission.
- Use WatchConnectivity for the Watch-to-iPhone handoff.
- Add CloudKit private-database sync only when cross-device backup or restore becomes a real product requirement.

CloudKit is the recommended first sync layer for this Apple-only app. It avoids a separate account system and custom REST service. Apple describes the private database as user-owned and accessible only to that user by default. The app must still support offline use, an absent iCloud account, export, and deletion.

A custom backend becomes justified when BrushCoach needs a service the device and CloudKit cannot provide: consented research-data collection, clinician or family sharing outside CloudKit sharing, Android/web clients, aggregate product analytics, remotely managed experiments, or server-side model training/inference.

## Data to keep for every completed session

The existing `BrushSession` is already close to the right durable record:

| Field | Purpose |
| --- | --- |
| `id` | Stable UUID for idempotent Watch transfer and future sync. |
| `startedAt`, `endedAt`, `duration` | Timeline and routine history. Preserve the original timezone offset or store a timezone identifier alongside the event if sessions will sync. |
| `source` | Distinguish Watch, phone, and manual entries. |
| `zonesCompleted`, `plannedZones` | Record what the pacer completed without rewriting history when the plan changes. |
| `verifiedZones` | Optional motion-verification result; `nil` remains different from zero. |
| `analysis` | Optional aggregate analysis: active seconds, fast-stroke seconds, position changes, longest held position, median stroke rate, coverage, completion state, and zone-agreement summary. |
| `flossed`, `tongueCleaned` | User-entered routine details. |
| `createdAt`, `updatedAt` | **Implemented.** `createdAt` is stamped by the device that built the record and survives the Watch transfer; `updatedAt` is stamped by whichever repository last wrote it. Legacy records decode both as `startedAt`. |
| `schemaVersion`, `analysisVersion` | Allow old records and results to remain interpretable after model or schema changes. |
| `deletedAt` | Optional tombstone so a deletion propagates to other devices. **Deliberately not implemented yet.** Deletion is still a hard delete. A tombstone nothing reads is a liability — it would need the repository to filter it, streak and history to skip it, and a purge path to stop the table growing. It lands with the sync layer that gives it meaning. |

Do not make motion analysis the authority for routine credit. Store it as an observation, matching the current model.

## Other local data

### Preferences

Keep reminder times, enabled periods, optional care prompts, brushing hand, and routine-day boundary on-device. Sync them only if users expect settings to follow them to a replacement iPhone. Notification and HealthKit authorization states are device state and must never be treated as portable preferences.

### Calibration profile

Keep `PersonalCalibrationProfile` local by default. It is user-specific, tied to a wrist/device setup, and can be regenerated. Store its schema version, feature schema version, creation date, watch wrist, quality score, and the model inputs already in the profile. Invalidate or rebuild it when its feature schema is incompatible.

### Operational diagnostics

If diagnostics are later added, collect the minimum needed to explain failures:

- App, watchOS, iOS, schema, and analysis versions.
- Watch model family and requested/actual sample rate, only if needed for compatibility work.
- Session transfer result, motion-recorder completion, covered seconds, window count, and coarse error code.
- Random installation identifier rather than a name, email address, advertising identifier, or precise location.

Diagnostics must be separable from brushing history, short-lived, and disclosed to the user.

## Raw motion traces

Do not upload or retain raw accelerometer, rotation, gravity, or attitude samples during normal brushing. The aggregate `SessionAnalysis` should be enough for the product experience.

Raw traces are appropriate only for an explicit calibration, debugging, or research flow. That flow should have:

- Separate, informed opt-in consent with a recorded consent-form version and timestamp.
- A clear label stating whether the trace is guided/calibration data or an ordinary session.
- A random participant ID; no name, email, location, contacts, or audio in the trace payload.
- Trace schema, app/OS versions, watch wrist, brushing hand when supplied, requested and actual sample rates, timestamps relative to trace start, prompted zone, and user-provided label provenance.
- Encryption in transit and at rest, a documented retention period, access controls, audit logs, export, and deletion.
- Object/file storage for the compressed trace payload; only searchable metadata belongs in a relational database.

Treat a prompted zone as a prompt, not ground-truth behavior. Research labels need provenance such as `prompted`, `self_reported`, or `observer_verified` so they are not later mistaken for verified training labels.

## Recommended evolution

### Phase 1: local-only MVP

Completed on `codex/backend-data-strategy`: the iPhone session history now uses a local SwiftData store backed by SQLite, with CloudKit explicitly disabled. A repository protocol keeps persistence out of the UI and domain model. Existing `brush-sessions.json` records are imported transactionally, and the JSON repository remains a recovery fallback if the database cannot open.

Preferences stay in `UserDefaults`, the personal calibration profile stays in its Watch-local file, and raw trace files remain local. Those stores already match their data's lifecycle and do not need to be forced into the session database.

Durable local data shapes (kept in the store appropriate to each lifecycle):

```text
Session
  id, startedAt, endedAt, timezoneIdentifier, duration
  source, zonesCompleted, plannedZones, verifiedZones
  flossed, tongueCleaned
  analysis fields (nullable)
  schemaVersion, analysisVersion, createdAt, updatedAt, deletedAt

Preferences
  morning/evening schedule, prompts, brushingHand, dayEndsAtHour
  schemaVersion, updatedAt

CalibrationProfile
  existing profile payload, device/wrist context, schema versions
  createdAt, supersededAt
```

### Phase 2: Apple-device sync

Sync user-owned session history through a CloudKit private database. Use stable UUID record names, an app-owned record zone, conflict metadata, and tombstones. The local store remains the source used by the UI; cloud sync runs opportunistically and never blocks a brushing session.

Do not sync authorization states. Consider keeping calibration device-local until there is evidence that transferring it across watches is valid.

### Phase 3: custom service, only if required

If research or cross-platform features justify a backend, use:

- Sign in with Apple or another explicit account layer.
- A versioned HTTPS JSON API for metadata and aggregate sessions.
- PostgreSQL for accounts, consent receipts, session metadata, diagnostics, and deletion state.
- Encrypted object storage with short-lived signed upload URLs for consented raw traces.
- Background, idempotent batch sync with `updatedAt`, server revisions, and deletion tombstones.

A minimal API could be:

```text
POST   /v1/sessions:batch-upsert
GET    /v1/sessions?changed_after=<cursor>
DELETE /v1/sessions/{id}
POST   /v1/research-traces/uploads
POST   /v1/research-traces/{id}:complete
GET    /v1/export
DELETE /v1/account
```

REST is a reasonable transport here, but it is an implementation detail rather than a product requirement. The hard parts are consent, authentication, offline conflict handling, deletion, retention, and keeping raw motion data out of the normal path.

## Privacy boundaries

- Do not collect data merely because a future model might use it.
- Do not use HealthKit-derived information for advertising or disclose it without the permissions and purpose Apple requires.
- Keep the app useful when HealthKit, notifications, diagnostics, research upload, or iCloud are declined.
- Give users an in-app explanation of stored data plus export and deletion controls before cloud storage ships.
- Avoid claiming that zone agreement is clinical accuracy or that BrushCoach diagnoses dental health.

## Revisit this decision when

- Users ask for restore/sync across iPhones.
- A non-Apple client is planned.
- Sharing with another person or clinician is a committed feature.
- A consented dataset is necessary to evaluate or train motion models.
- Remote configuration, subscription enforcement, or server-side computation becomes necessary.

## References

- Apple, [Providing User Access to CloudKit Data](https://developer.apple.com/documentation/cloudkit/providing-user-access-to-cloudkit-data)
- Apple, [Encrypting User Data](https://developer.apple.com/documentation/cloudkit/encrypting-user-data)
- Apple, [Protecting User Privacy in HealthKit](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
