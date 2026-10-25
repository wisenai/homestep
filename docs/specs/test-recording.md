# Spec: test-walk recording

**Code:** `Core/Sources/HomeStepCore/SessionLogger.swift`, `GuideRules.swift` (`Reading.logFields`); `tools/pull-logs.sh`, `tools/analyze-log.py`.
**Tests:** `Core/Tests/HomeStepCoreTests/StorageTests.swift`, `GuideRulesTests.swift`; `tools/tests/test_analyze_log.py`.
**Requirements:** REQ-LOG-*.

Thresholds are set from what the detector measured on real walks, not from guesses. In developer mode each Start begins a new file, `Documents/sessions/session-<ISO time>.jsonl`, one JSON object per line. Every row has `t` (Unix time, seconds) and `kind`.

| kind | When | Other fields |
|---|---|---|
| `session` | file opened | `device` (hardware model) |
| `start` | Start | `warnDistance`, `lowPower` |
| `reading` | about 8 a second | the reading fields below |
| `event` | every event except `clear` | `event` (name, below), `reading` |
| `mark` | MARK WRONG | `label: "wrong"`, `reading` |
| `aimFault` | "Cannot see the floor" said | `pitch`, `near` |
| `warnDistance` | the setting changed | `value` |
| `delegateRestored` | the camera view took over the session's delegate and it was put back | |
| `stop` | Stop | |

**Reading fields:** `near`, `far` (points in each strip), `pitch` (degrees down), `swing` (degrees a second), `speed` (m/s), `walking`, and when known and finite: `ref` (reference height), `probe` (probe median), `low` (probe 15th percentile), `drop` (ref − low), `obstacle` (m), `fallCov`, `riseCov` (shares of the probe strip).

**Event names:** `step:Step down. d=0.46 spoken=true`, `proximity`, `hazard:<words>`, `landmark:<number>`.

The buffer is written at most once a second, and a file stops growing at 40 MB (about six hours of walking). Nothing is recorded unless developer mode is on, and recordings never leave the phone except by cable with `tools/pull-logs.sh`.

## Analysis

`python3 tools/analyze-log.py logs/session-….jsonl` prints:

1. Length, number of readings, events and marks.
2. What was heard: events grouped into episodes (same event, less than 1 s apart), with start time and length.
3. Every MARK WRONG with its reading.
4. The noise floor: |drop| on level floor (under 0.05 m), median, 90th percentile and maximum; real level changes (0.05 m or more); and the margin between the two.
5. Pitch, swing and speed percentiles, and frames with an empty reference strip.
