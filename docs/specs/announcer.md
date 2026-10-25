# Spec: announcer

**Code:** `Core/Sources/HomeStepCore/Announcer.swift` (`AnnouncerPolicy`, the rules), `Sources/HomeStep/Announcer.swift` (plays them with AVFoundation and Core Haptics).
**Tests:** `Core/Tests/HomeStepCoreTests/AnnouncerPolicyTests.swift`.
**Requirements:** REQ-OUT-*, REQ-SAFE-02, REQ-SAFE-03, REQ-OBST-05, REQ-OBST-06, REQ-CLEAR-02.

Everything HomeStep says, beeps or buzzes goes through one announcer, so a warning can never be talked over by something less urgent. The policy takes an event and the time and returns a list of sounds (`stopSpeaking`, `speak`, `play` tones, `stopTones`, `vibrate`); the app plays them in order. Because the policy never touches audio itself, every rule below is tested with a fake clock.

## Sounds

| Sound | Tones | Meaning |
|---|---|---|
| Warning | 1568 Hz, 0.09 s; gap 0.05 s; 1568 Hz, 0.09 s | A hazard code: stop and listen |
| Step beep | 1200 Hz, 0.05 s; gap 0.04 s; 1200 Hz, 0.05 s | The floor ends (or rises) ahead |
| Obstacle beep | one 0.07 s tone, 300 Hz far to 800 Hz near | Something in the way: go around |
| Chime | 880 Hz, 0.10 s; gap 0.04 s; 660 Hz, 0.14 s | The app's own state, not a warning |

Steps are high and doubled, obstacles single and low, because they mean opposite things. When the obstacle beep went up to 1400 Hz, a near obstacle sounded like a step warning.

## Events

| Event | What happens | Settings that apply |
|---|---|---|
| `hazard(text)` | stop speech now, warning sound, full vibration, say text | none |
| `step(text, d, speak)` | step beep and vibration (1 − d/0.8) if due; if `speak`: stop speech now, say text | none |
| `proximity(d, i)` | "Obstacle ahead." if due; obstacle beep if due; vibration | speech, tones, vibration, STOP BEEPING |
| `clear` | "Proceed." if due | speech, STOP BEEPING |
| `landmark` (hazard kind) | same as `hazard` with the landmark's words | none |
| `landmark` (plain) | say its words, unless the same landmark was said within 4 s | speech |

Other calls:

| Call | Used for | What happens |
|---|---|---|
| `alert(text)` | paused, resumed, failed, no LiDAR, aim fault | stop speech now, chime, say text; ignores the speech switch |
| `status(text)` | replies to Start, "Where am I?", settings | stop speech at the end of the word, say text; ignores the speech switch |
| `say(text)` | ordinary speech | follows the speech switch |
| `sayThrottled(text)` | messages a stray tap could repeat | same text at most every 20 s |
| `silence()` | Stop, STOP BEEPING | stop speech now, drop queued tones, let the next warning speak at once |

## Timing

| Rule | Value |
|---|---|
| Same warning words not repeated within | 2.5 s |
| Step beep interval | 0.12 + 0.55 × min(d / 0.8, 1) s |
| Obstacle beep interval | 0.6 − 0.48 × intensity s |
| "Obstacle ahead" | on a new obstacle (none for 1.5 s), then at most every 6 s |
| Same landmark not repeated within | 4 s |
| "Proceed" | at most every 2 s; not within 2.5 s of a spoken warning or "Obstacle ahead" |

## Vibration

- Warnings and step beeps vibrate whatever the vibration switch says.
- Obstacles vibrate if the switch is on, and always when tones are off, so an obstacle always reaches the walker somehow.
