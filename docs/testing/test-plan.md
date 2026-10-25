# Test plan

HomeStep is tested at five levels. The first three run on any Mac in a few minutes; the last two need people.

| Level | What | Where | How to run | Needs |
|---|---|---|---|---|
| 1. Core unit tests | The rules: detector, announcer, places, codes, settings, recorder, guide messages | `Core/Tests/HomeStepCoreTests/` | `make test-core` | A Mac with Xcode |
| 2. Walk scenarios | Whole approaches to steps, obstacles and furniture, frame by frame at 60 fps, with the cane sweeping, through a synthetic room rendered as LiDAR depth | `Core/Tests/HomeStepCoreTests/WalkScenarioTests.swift`, `Support/SyntheticRoom.swift` | part of `make test-core` | A Mac |
| 3. App tests | Printed sheets (QR reads back), first launch, safety page, setting up a place | `Tests/`, `UITests/` | `make test-app` | Xcode and an iOS Simulator |
| 4. Checks | No networking code; only the camera permission; privacy manifest; every requirement traced | `tools/check.py`, `tools/trace.py` | `make check` | Python 3 |
| 5. Field protocols | The real step, real obstacles, real codes, failures, sound | `field-protocols.md` | by hand | The phone on the stick, a spotter |

`make test` runs levels 1 to 4. CI (`.github/workflows/ci.yml`) runs levels 1, 2 and 4 on every push.

## What the synthetic room can and can't tell us

It renders depth exactly as a pinhole LiDAR would see a room made of flat floor strips and boxes, with about 4 mm of noise, from a camera 0.92 m up and 45° down on a sweeping stick. That makes the detector's geometry and timing testable, and it found KI-1. It doesn't model shiny or dark floors, rugs, missing returns from real materials, ARKit's position wobble, or a person's gait. Those are what the field protocols and the recorded walks are for. A change to a threshold should be argued from a recorded walk (`tools/analyze-log.py`), checked in the scenarios, and then confirmed with FP-1.

## Inspection checklist

For requirements verified by inspection, before each release:

- [ ] **REQ-SAFE-06:** read every string in `Sources/HomeStep/` and the README. Nothing says or implies the cane, a guide dog or people can be dropped. ("Supplements", "extra warning", "use your cane" are the right register.)
- [ ] **REQ-STEP-09:** the warn-distance control in Settings and on the guide screen stays inside 0.30–0.90 m and speaks the new value.
- [ ] **REQ-PLACE-09:** `GuideController.init` announces place changes while guiding.
- [ ] **REQ-GUIDE-01:** `GuideController.start()` checks ARKit support and camera access first, sets `worldAlignment = .gravity`, turns on `sceneDepth` when supported, sets `isIdleTimerDisabled`.
- [ ] **REQ-GUIDE-08:** `start()` says "Low power mode is on." when it is.
- [ ] **REQ-UI-01:** the guide screen's controls are in the top half; STOP BEEPING, Start/Stop and Where am I? are at least 48 points tall; every control has a VoiceOver label or hint.

## Adding or changing a requirement

1. Edit `docs/requirements.md`: a `### REQ-AREA-NN Title` heading, the statement, and a **Verified by** line.
2. Write the test first, with `// REQ-AREA-NN` above it, and watch it fail.
3. Change the code until it passes.
4. Run `make test`. `tools/trace.py` updates `docs/traceability.md` and fails if anything is untraced.
5. If it touches steps or obstacles, run the field protocol it names before telling anyone to rely on it.
