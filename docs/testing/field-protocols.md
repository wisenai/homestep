# Field protocols

What can only be checked with the phone on the stick in a real house. Record every run in the table at the end of each protocol (copy it into `docs/testing/results/<date>-<protocol>.md`). A protocol passes only when every row passes. Turn on developer mode for every run, so the recording can be checked afterwards with `tools/analyze-log.py`.

**Rig:** the phone clamped about halfway up the walking stick, upright, rear camera forward, aim hint showing "Aim OK" while standing on flat floor. Warn distance at its default (0.45 m) unless the protocol says otherwise. Normal indoor light. A sighted spotter walks beside the tester at every step test.

## FP-1: the step gate (REQ-STEP-13, REQ-STEP-14, REQ-STEP-15, REQ-STEP-16, REQ-SAFE-07)

At a real step (ours: about 0.17 m into the sunken living room).

1. Start 3 m from the step. Walk towards it at a normal pace, sweeping the stick, until the warning, then stop.
2. Pass if "Step down" (or "Step up" from below) is heard and the walker can stop before the stick's tip passes the edge.
3. Mark the walker's toe position when the words came; measure its distance to the edge.

| Set | Direction | Codes | Trials | Pass needed |
|---|---|---|---|---|
| A | down into the room | in place | 10 | 10 |
| B | up out of the room | in place | 10 | 10 |
| C | down | **covered** (LiDAR only) | 10 | 10 |
| D | up | covered | 10 | 10 |
| E (KI-1, REQ-STEP-16) | down | covered, warn distance 0.30, 0.35, 0.40 m | 3 each | record whether words are heard at all |

| Date | Set | Trial | Words heard? | Toe to edge (m) | Pass? | Notes |
|---|---|---|---|---|---|---|
| | | | | | | |

## FP-2: obstacles (REQ-OBST-01, REQ-OBST-05, REQ-OBST-06)

1. A chair, then a box at least 0.3 m tall, then a door half open, each in the walking line. Walk towards each from 2 m.
2. Pass if the low beep starts by 0.9 m, speeds up as you get closer, "Obstacle ahead" is said once, and no step warning is given.
3. Walk past a wall and a door frame at 0.5 m to one side: pass if no obstacle beep.

| Date | Object | Beep by 0.9 m? | Speeds up? | Words once? | No step warning? | Pass? |
|---|---|---|---|---|---|---|
| | | | | | | |

## FP-3: codes (REQ-MARK-07, REQ-OUT-04, REQ-MARK-04)

1. Print the sample place's four codes; tape them as their notes say.
2. Walk past each from about a stride away.
3. Pass if each name is said once as you pass, and the step codes interrupt with the warning sound.
4. Hold an unrelated QR code (a web address) in view: pass if nothing is said.

| Date | Code | Heard? | Distance | Pass? |
|---|---|---|---|---|
| | | | | |

## FP-4: starting, and failures are said (REQ-GUIDE-01, REQ-SAFE-04, REQ-GUIDE-04, REQ-GUIDE-06)

| Do this | Expect | Pass? |
|---|---|---|
| Press Start | "Guiding." and the place; the screen stays on while guiding | |
| Turn camera access off in the iPhone's Settings, press Start | "HomeStep needs the camera…" and guiding doesn't start | |
| Lock the phone, then unlock it | "Guidance paused. Use your cane." then "Guidance resumed." | |
| Pull down Control Center for 5 s | a pause or stop message, then "Guidance resumed." | |
| Cover the rear cameras for 5 s | "Cannot see the floor. Tilt the phone down." | |
| Tilt the phone level for 5 s | "Cannot see the floor. Tilt the phone down." | |
| Start in Low Power Mode | "Low power mode is on." | |

## FP-5: no LiDAR (REQ-GUIDE-02)

On an iPhone without LiDAR: press Start. Pass if it says "Step detection needs a LiDAR iPhone. Reading markers only. Use your cane.", the screen says steps are not detected, and a code is still read.

## FP-6: sound and the Action button (REQ-OUT-09, REQ-GUIDE-09)

1. With a single earpiece and music playing: the music gets quieter during speech instead of stopping.
2. Assign "Where am I?" to the Action button in the iPhone's Settings; after passing a code, press it: pass if the last code's name is said.
