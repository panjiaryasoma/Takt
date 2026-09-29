# Takt Mobile

Flutter source scaffold.

If Android/iOS runner directories have not been generated on your machine:

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter test
flutter run
```

Do not let generated calendar UI blur the authority boundary:

```text
suggested work window != accepted commitment
```

## 3B Decision Report

3B owns strict response parsing, the immutable evaluation session, report presentation,
candidate selection, confirmation, and decision intents. The screen reuses the
existing Steffi theme and card layout. It has no HTTP client or database dependency.

The 4B integration host supplies `decisionSession`, `currentInputRevision`,
`onAcceptCandidate`, `onEditConstraints`, and `onIgnoreRecommendation` to `TaktApp`
(or supplies the equivalent inputs directly to `RekomendasiJadwalScreen`).
Without a session, the existing 2B analysis flow remains available. Tests use
explicit wire fixtures under `test/support`; production never installs a demo session.
Both backend and Flutter tests also read the same contract golden at
`tests/fixtures/api/plan_evaluate_response_v1.json` (from the repository root).
The backend validates that JSON and compares it with `evaluate_plan` output using
the fixed request, clock and evaluation ID in `test_plan_evaluate_behavior.py`;
Flutter parses the file unchanged. Update it deliberately with any wire contract
change. This checks producer/consumer compatibility; real API integration remains
part of 4B.

Host contract:

- Own authoritative inputs, request generation, late-response rejection and active
  session replacement. Pair the exact request/response and check report/snapshot
  identity before publishing `EvaluationSession.fromRaw(...)`.
- `fromRaw` is the only session constructor. The original request is opaque to 3B;
  the original response is parsed internally into deeply immutable DTOs.
- Push the current input revision into the component when authoritative inputs
  change. Invalidated sessions cannot regain action authority without replacement.
- Replacing a session cancels pending confirmation even at the same input revision.
  Confirmation freezes the session, generation, evaluation and candidate identity.
- Accept receives the exact session and intent once per confirmed handoff. 4B must
  revalidate active session/revision at its persistence boundary and own persistent
  idempotency. Callback completion does not authorize a 3B "saved/booked" claim.
- Edit Constraints emits an intent. 4B opens its real editor, changes inputs, bumps
  revision, evaluates, and publishes a new session. Ignore dismisses the suggestion.

Readiness and feasibility stay separate. Blocked readiness explains its specific
gate (review, missing information, unmet eligibility or passed deadline), while
feasibility remains unevaluated. Primary recommendation never changes when
the user selects an alternative. Only backend-allowed actions are rendered; missing
host handlers disable Accept/Edit rather than silently pretending success.
Timestamps are shown in device local time with explicit UTC offsets.

HTTP, planning-input assembly, workload/availability generation, authoritative
constraint mutation, persistence, Saved Plans and re-evaluation remain 4B work.
Issue #7 component behavior can be tested here; real edit-to-evaluate and the
Technical MVP end-to-end remain dependent on that host.

Verification: `flutter analyze`, `flutter test`, `flutter build apk --debug`, and
the existing backend regression suite. Results must be associated with the tested
commit, not inherited from an earlier baseline.
