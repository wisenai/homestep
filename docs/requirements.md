# HomeStep requirements

Every requirement has an ID, a statement, the reason for it, and how it is verified. Tests name the requirement they check in a comment (`// REQ-STEP-03`), and `tools/trace.py` fails the build if an automatically verified requirement has no test, or a test names a requirement that doesn't exist. The current map is in [`traceability.md`](traceability.md).

**Verified by:**

- `unit`: a test in `Core/Tests` (runs with `swift test`, no phone needed) or `Tests/`.
- `scenario`: a whole simulated walk through a synthetic room, frame by frame (`Core/Tests/.../WalkScenarioTests.swift`).
- `ui`: the UI test in `UITests/`, in the Simulator.
- `check`: a script in `tools/` that inspects the code or the project.
- `field`: a protocol run by hand with the phone on the stick, in `testing/field-protocols.md`.
- `inspection`: a person reads the code or the screens against the checklist in `testing/test-plan.md`.

The numbers below are the defaults in `StepDetector.Settings` and `AnnouncerPolicy`. Requirements that come from the product goals are marked with the goal (G1 to G6, see [`product/PRD.md`](product/PRD.md)).

---

## Safety (SAFE)

These outrank everything else.

### REQ-SAFE-01 No network
The app shall contain no networking code: no URL sessions, sockets or web views. The step warning shall never depend on a connection. (G6)
- **Why:** a warning that needs the internet can be late or missing. Nothing should leave the phone.
- **Verified by:** check

### REQ-SAFE-02 Warnings ignore the settings
Step and hazard warnings shall play, with their sound and vibration, whatever the speech, tones and vibration switches say.
- **Why:** someone turning speech off to stop "Proceed" must not also turn off "Step down".
- **Verified by:** unit

### REQ-SAFE-03 Nothing mutes a step warning
No control shall silence future step or hazard warnings. STOP BEEPING shall mute obstacle beeps, "Obstacle ahead" and "Proceed" only.
- **Verified by:** unit

### REQ-SAFE-04 Never fail silently
When guidance stops working (camera frames stop, the session is interrupted or fails, or the phone has no LiDAR), the app shall say so out loud, and the message shall end "Use your cane." (G5)
- **Why:** to someone who can't see the screen, an app that has quietly stopped sounds exactly like a clear path.
- **Verified by:** unit, field

### REQ-SAFE-05 Safety page first
On first launch the app shall show a page saying HomeStep supplements the cane, can miss things, is not a medical device and is not for outdoor or emergency use, and shall not continue until it is acknowledged with its button.
- **Verified by:** ui

### REQ-SAFE-06 No over-promising
No text in the app or its documents shall suggest the walker can stop using their cane, guide dog or the people around them.
- **Verified by:** inspection

### REQ-SAFE-07 A marked step is caught twice
A step shall be detected by LiDAR with no code present, and a code tagged as a step shall also play as a warning, so a marked step has two independent detectors.
- **Verified by:** unit, scenario

### REQ-SAFE-08 Lean early
Thresholds shall default to warning early: the step-down threshold (0.07 m) well under a real step (about 0.17 m), and the spoken warning at least 0.30 m before the edge at the default warn distance.
- **Verified by:** scenario

---

## Steps (STEP)

The detector is specified in detail in [`specs/step-detector.md`](specs/step-detector.md). (G1)

### REQ-STEP-01 Heights, not distances
The detector shall turn each depth reading into a point in ARKit's gravity-aligned world and judge the floor by its height, so tilting or rotating the phone does not change the result.
- **Why:** a swinging stick tilts the phone by more than the size of a step; distance along a ray changes with tilt, height doesn't.
- **Verified by:** unit

### REQ-STEP-02 Same-frame comparison
The floor ahead shall be compared with the floor just in front of the stick from the same frame, so an error in ARKit's position estimate affects both equally.
- **Why:** comparing against a floor height remembered from earlier frames produced false "Step down" warnings during normal walking.
- **Verified by:** unit

### REQ-STEP-03 Step down
When at least 15% of the probe strip lies more than 0.07 m below the reference floor, the detector shall report a step down.
- **Verified by:** unit

### REQ-STEP-04 Step up
When at least 60% of the probe strip lies more than 0.07 m above the reference floor, and the median rise is between 0.07 m and 0.22 m, the detector shall report a step up.
- **Verified by:** unit

### REQ-STEP-05 Furniture is not a step
A raised patch with floor still visible around it (a footstool, a chair seat) shall not be reported as a step up.
- **Verified by:** unit, scenario

### REQ-STEP-06 Floor that vanishes
When the reference floor is visible, the probe strip returns fewer than 12 points and nothing is in the way, the detector shall report a step down. It shall not do so when an obstacle could be hiding the floor.
- **Verified by:** unit

### REQ-STEP-07 Confirmation
A step shall be reported only after 3 frames in a row agree on its direction, or 5 when the phone is turning faster than 60° a second. A change of direction shall start the count again.
- **Why:** a single noisy frame must not speak, and a fast sweep smears the depth image.
- **Verified by:** unit

### REQ-STEP-08 Where the edge is
The detector shall report the distance to the near edge of the step. Beeping shall start as soon as a step is confirmed; the words shall wait until the edge is within the warn distance.
- **Verified by:** unit

### REQ-STEP-09 Warn distance
The warn distance shall default to 0.45 m, be adjustable from 0.30 m to 0.90 m in 0.05 m steps, be kept between launches, and be confirmed out loud when changed.
- **Verified by:** unit, inspection

### REQ-STEP-10 Fresh start
The detector shall forget what earlier frames saw when guidance starts or resumes after an interruption.
- **Verified by:** unit

### REQ-STEP-11 Bad readings
Readings that are not finite, nearer than 0.1 m, farther than 5 m, or marked low confidence by ARKit shall be ignored, and a strip with fewer than 12 points shall decide nothing.
- **Verified by:** unit

### REQ-STEP-12 Quiet on flat floor
Walking on level floor with the cane sweeping shall produce no step reports.
- **Why:** a warning that cries wolf gets ignored, which is its own hazard.
- **Verified by:** scenario

### REQ-STEP-13 In time for a step down
Walking towards a 0.17 m step down at 0.5 m/s with the cane sweeping, beeping shall start at least 0.45 m before the edge and "Step down" shall be spoken at least 0.30 m before it, at the default warn distance. A longer warn distance shall speak earlier.
- **Verified by:** scenario, field

### REQ-STEP-14 In time for a step up
Walking towards a 0.17 m step up, "Step up" shall be spoken at least 0.30 m before the edge, and "Step down" never.
- **Verified by:** scenario, field

### REQ-STEP-15 At the real step
At the real step, with the phone on the stick, the warning shall come early enough to stop on 10 of 10 approaches from each direction, and on 10 of 10 with the step's codes covered.
- **Verified by:** field

### REQ-STEP-16 Every setting speaks
For every warn distance the setting allows, a step shall be spoken, not only beeped, before it is reached.
- **Status:** **open, known issue KI-1.** In the simulated walks, warn distances of 0.30 to 0.40 m beep but never speak. See [`specs/step-detector.md`](specs/step-detector.md#known-issues). The test is marked as an expected failure until this is settled at the real step.
- **Verified by:** scenario, field

---

## Obstacles (OBST)

(G2)

### REQ-OBST-01 What counts
Anything more than 0.25 m above the floor, within 0.90 m ahead and 0.35 m either side of the walking line, shall be an obstacle.
- **Verified by:** unit, scenario

### REQ-OBST-02 Persistence
An obstacle shall be reported only after 3 frames in a row.
- **Verified by:** unit

### REQ-OBST-03 Closer is stronger
The obstacle's intensity shall be 1 minus its distance over 0.90 m, between 0 and 1.
- **Verified by:** unit

### REQ-OBST-04 Steps first
When a step and an obstacle are both seen in one frame, the step shall be reported.
- **Verified by:** unit

### REQ-OBST-05 Obstacle beep
An obstacle shall sound as one low tone, 300 Hz far to 800 Hz near, repeating every 0.6 s far to 0.12 s near, always below the 1568 Hz warning sound. It shall vibrate if vibration is on, and always when tones are off.
- **Verified by:** unit

### REQ-OBST-06 Obstacle words
"Obstacle ahead." shall be said when an obstacle appears after at least 1.5 s without one, and at most every 6 s while it stays.
- **Verified by:** unit

### REQ-OBST-07 Unknown is not an obstacle
With no floor in view, the detector shall report nothing rather than an obstacle.
- **Why:** a swept cane loses the floor for a frame or two all the time; treating that as an obstacle beeped at nothing and blocked "Proceed".
- **Verified by:** unit

---

## All clear (CLEAR)

(G5)

### REQ-CLEAR-01 Only while walking
"Proceed" shall be reported only when no step or obstacle is seen, the floor just ahead is visible, and the walker is moving at 0.10 m/s or more (median over 20 frames).
- **Why:** telling someone who has stopped to proceed would override their own decision.
- **Verified by:** unit

### REQ-CLEAR-02 Timing
"Proceed." shall be said at most every 2 s, and not within 2.5 s of a spoken warning or of "Obstacle ahead".
- **Verified by:** unit

---

## Output (OUT)

Specified in [`specs/announcer.md`](specs/announcer.md).

### REQ-OUT-01 Warnings interrupt
A warning shall stop any speech immediately, play two 1568 Hz beeps, vibrate at full strength, and then speak.
- **Verified by:** unit

### REQ-OUT-02 No machine-gunning
The same warning words shall not be repeated within 2.5 s. Different words (such as "Step up" after "Step down") shall never be held back. The step beep continues during the gap.
- **Verified by:** unit

### REQ-OUT-03 Step beep
A step shall sound as a double 1200 Hz beep, 0.67 s apart at 0.8 m or more and 0.12 s apart at the edge, with a vibration that grows as the edge gets closer. It shall never be muted.
- **Verified by:** unit

### REQ-OUT-04 Landmark cooldown
A landmark shall not be repeated within 4 s; a different landmark shall be spoken straight away.
- **Verified by:** unit

### REQ-OUT-05 System messages
Messages about the app's own state shall interrupt speech, play an 880/660 Hz chime that differs from the warning sound, and always be spoken.
- **Verified by:** unit

### REQ-OUT-06 Replies
The reply to something the user did (Start, "Where am I?", a setting) shall always be spoken.
- **Verified by:** unit

### REQ-OUT-07 Stop
Stop and STOP BEEPING shall silence speech and queued tones at once and allow the next warning to speak immediately.
- **Verified by:** unit

### REQ-OUT-08 Speech switch
Landmarks, "Obstacle ahead", "Proceed" and other ordinary speech shall follow the speech switch.
- **Verified by:** unit

### REQ-OUT-09 One ear free
Audio shall lower other apps' sound rather than stop it, and work through a single earpiece or bone-conduction headset.
- **Verified by:** field

---

## Codes and landmarks (MARK)

Specified in [`specs/places-and-codes.md`](specs/places-and-codes.md). (G3)

### REQ-MARK-01 Code format
A code shall hold `akshi:<n>` (any letter case) or a bare number, with n from 0 to 9999. Anything else shall be ignored. New codes shall be printed as `akshi:<n>`.
- **Verified by:** unit

### REQ-MARK-02 Unknown numbers
A code whose number is not in the place in use shall be ignored.
- **Verified by:** unit

### REQ-MARK-03 What is said
A landmark shall say its custom words if given, otherwise its name. A step, stairs or hazard shall always start with what it is ("Step down.", "Stairs.", "Caution.") unless the custom words already say it.
- **Verified by:** unit

### REQ-MARK-04 Hazard codes are warnings
Landmarks of kind step down, step up, stairs or other hazard shall play as warnings (REQ-OUT-01).
- **Verified by:** unit

### REQ-MARK-05 Printed sheets
The app shall print one US Letter page per landmark with a 6-inch QR code (high error correction) that reads back to its number, the landmark's name and kind, and where to tape it.
- **Verified by:** unit

### REQ-MARK-06 Numbers are assigned
A new landmark shall get the lowest unused number from 1; numbers are never typed.
- **Verified by:** unit, ui

### REQ-MARK-07 Reading on the phone
Codes shall be read with Apple's Vision framework from the live camera, from about a stride away, in normal indoor light.
- **Verified by:** field

---

## Places (PLACE)

(G4)

### REQ-PLACE-01 Saved on the phone
Places shall be saved on the phone only, in one file written atomically, with iOS file protection.
- **Verified by:** unit

### REQ-PLACE-02 Which place is in use
The first place added shall be put in use. Importing a place shall not replace the place already in use.
- **Verified by:** unit

### REQ-PLACE-03 Deleting the place in use
Deleting the place in use shall leave no place in use rather than switching to another.
- **Why:** every place numbers its codes from 1, so a silent switch would change what the codes on the walls mean.
- **Verified by:** unit

### REQ-PLACE-04 Sharing
A place shall export as a `.homestep` file and import with new identities. The first version's `home_map.json` shall also import. Anything else shall be refused.
- **Verified by:** unit

### REQ-PLACE-05 Duplicate numbers
On import, landmarks sharing a number shall be renumbered, hazards first, so a printed hazard code keeps meaning the hazard.
- **Verified by:** unit

### REQ-PLACE-06 Damaged file
An unreadable places file shall be kept (renamed, never overwritten) and the user told that no places were loaded.
- **Verified by:** unit

### REQ-PLACE-07 Sample place
A sample place with four codes, including both sides of one step, shall be available.
- **Verified by:** unit

### REQ-PLACE-08 Ready for the camera thread
Every change to the place in use shall be visible to the camera thread straight away.
- **Verified by:** unit

### REQ-PLACE-09 Changes are said
Changing the place in use while guiding shall be said out loud.
- **Verified by:** unit, inspection

---

## Guiding (GUIDE)

Specified in [`specs/guide-session.md`](specs/guide-session.md).

### REQ-GUIDE-01 Starting
Start shall check that the phone supports ARKit world tracking and that camera access is allowed, saying what is wrong if not; run ARKit gravity-aligned, with LiDAR depth when available; and keep the screen awake while guiding.
- **Verified by:** inspection, field

### REQ-GUIDE-02 No LiDAR
On an iPhone without LiDAR, codes shall still be read, and the app shall say "Step detection needs a LiDAR iPhone. Reading markers only. Use your cane." and show it on screen.
- **Verified by:** unit, field

### REQ-GUIDE-03 Start is answered
Start shall always be answered out loud ("Guiding." and the place, or what is wrong).
- **Verified by:** unit

### REQ-GUIDE-04 Stalls
If no camera frame arrives for more than 2.5 s while guiding, the app shall say "Guidance stopped. Use your cane." once, and "Guidance resumed." when frames return, starting the detector fresh.
- **Verified by:** unit, field

### REQ-GUIDE-05 Aim hint
While guiding, the screen shall show whether the phone is aimed well: tilt between 25° and 58° below horizontal, with floor visible both just ahead and further out.
- **Verified by:** unit

### REQ-GUIDE-06 Aim fault out loud
If the floor just ahead is out of view for 3 checks in a row (once a second), the app shall say "Cannot see the floor. Tilt the phone down.", at most every 12 s.
- **Why:** a whole test walk was lost to a phone aimed too flat; the screen said so, but nobody was looking at it.
- **Verified by:** unit

### REQ-GUIDE-07 Where am I?
"Where am I?" shall say the last landmark read and how long ago, or that none has been read.
- **Verified by:** unit

### REQ-GUIDE-08 Low Power Mode
Starting in Low Power Mode shall be mentioned out loud.
- **Verified by:** inspection

### REQ-GUIDE-09 Action button
"Where am I?" shall be available to the iPhone's Action button, Shortcuts and Siri.
- **Verified by:** field

---

## Test recording (LOG)

Specified in [`specs/test-recording.md`](specs/test-recording.md).

### REQ-LOG-01 Recorder
In developer mode, a test walk shall be recorded on the phone as JSON lines: the session, start, about 8 readings a second, every event except "clear" with the numbers behind it, MARK WRONG presses, aim faults and stop.
- **Verified by:** unit

### REQ-LOG-02 Reading fields
Each reading shall carry the keys the analysis script reads (`near`, `far`, `pitch`, `swing`, `speed`, `walking`, and `ref`, `probe`, `low`, `drop`, `obstacle`, `fallCov`, `riseCov` when known), leaving out non-finite numbers.
- **Verified by:** unit

### REQ-LOG-03 Size cap
A recording shall stop growing at 40 MB.
- **Verified by:** unit

### REQ-LOG-04 Analysis
`tools/analyze-log.py` shall summarise a recording: what was heard and when, MARK WRONG presses, the flat-floor noise of `drop`, real level changes, and the margin between them.
- **Verified by:** unit

### REQ-LOG-05 Event names
Events shall be logged with a short readable name, such as `step:Step down. d=0.46 spoken=true`.
- **Verified by:** unit

---

## Settings and screens (SET, UI)

### REQ-SET-01 Settings
Speech, tones and vibration shall default on, speaking rate 0.5 (range 0.35 to 0.65), developer mode off, and all shall be kept between launches.
- **Verified by:** unit

### REQ-UI-01 Large and labelled
The guide screen's controls shall be large, high contrast, labelled for VoiceOver, and in the top half of the screen (the mount covers the bottom).
- **Verified by:** ui, inspection

### REQ-UI-02 See what HomeStep sees
The visualization shall colour each point exactly as the detector classifies it, using the same thresholds, and only while the screen is open.
- **Verified by:** unit

---

## Privacy (PRIV)

### REQ-PRIV-01 Nothing collected
The camera shall be the only permission requested, camera images shall never be saved, and the privacy manifest shall declare no tracking and no collected data. (G6)
- **Verified by:** check
