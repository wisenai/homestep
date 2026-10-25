# Hazard analysis

What could go wrong for the person walking, why, what HomeStep does about it, and how that is checked. Severity: **High** could cause a fall or injury, **Medium** could mislead or erode trust, **Low** is an annoyance. "Left over" is what remains after the mitigation; it is why the cane always comes first.

| # | Hazard | Causes | Severity | Mitigation | Requirements | Left over |
|---|---|---|---|---|---|---|
| H1 | A step down is not warned about | phone aimed too flat or steep; dark or shiny floor; fast sweep; detector fault | High | LiDAR detection with no setup; a step code as a second, independent detector; early thresholds; spoken aim fault; "floor vanished" rule | SAFE-07, SAFE-08, STEP-03, STEP-06, STEP-13, STEP-15, GUIDE-06 | Field gate FP-1 not yet run; KI-2 |
| H2 | The warning comes too late to stop | warn distance too short; slow confirmation | High | Beeping starts before the words and speeds up; warn distance adjustable; 3-frame confirmation (about 50 ms) | STEP-07, STEP-08, STEP-13, OUT-03 | **KI-1: warn distances 0.30 to 0.40 m beep but don't speak in simulation** |
| H3 | A step up is not warned about | as H1 | High | Step-up rule; step-up codes | STEP-04, STEP-14 | As H1 |
| H4 | The app stops working without saying so | phone locked, call, background, overheating, ARKit error | High | Stall check every second; interruption and failure messages, all ending "Use your cane." | SAFE-04, GUIDE-04 | A crashed app can't speak; the walker hears nothing new, which is why "Proceed" repeats while walking |
| H5 | Silence is taken to mean "clear" | nothing to report | Medium | "Proceed" every couple of seconds while walking; Start always answered | CLEAR-01, CLEAR-02, GUIDE-03 | |
| H6 | Too many false warnings, so warnings get ignored | swing; noise; furniture; door frames | Medium | Height in the gravity frame, same-frame comparison, coverage tests, persistence; flat-floor scenario tests; recorded walks and MARK WRONG | STEP-01, STEP-02, STEP-05, STEP-12, OBST-02, LOG-01 | |
| H7 | An obstacle is confused with a step, or the reverse | similar sounds | Medium | Different sounds: double high beep vs single low beep; the warning sound at 1568 Hz, obstacles never above 800 Hz | OUT-01, OUT-03, OBST-05 | |
| H8 | A warning is muted by a setting | speech or tones turned off | High | Warnings ignore all switches; STOP BEEPING mutes obstacles and "Proceed" only | SAFE-02, SAFE-03 | |
| H9 | A warning is cut off or repeated so fast it's never heard as words | the detector reports every frame | Medium | 2.5 s repeat gap keyed on the words | OUT-02 | |
| H10 | "Proceed" said to someone standing at a step | all-clear after a warning | Medium | "Proceed" only while walking, and not within 2.5 s of a warning | CLEAR-01, CLEAR-02 | |
| H11 | Codes mean the wrong thing | place switched silently; duplicate numbers on import | Medium | Deleting the place in use leaves none; imports don't replace the place in use; place changes are said; duplicates renumbered with hazards first | PLACE-02, PLACE-03, PLACE-05, PLACE-09 | |
| H12 | Saved places lost, so hazard codes stop working | damaged file; failed save | Medium | Damaged file kept; user told | PLACE-06 | |
| H13 | Some other QR code is taken for a HomeStep code | signs, menus, Wi-Fi codes | Low | Only `akshi:<n>` or a bare number up to 9999; never opens links | MARK-01 | A QR code containing just a number would be read |
| H14 | The walker relies on HomeStep instead of the cane | over-promising | High | Safety page that must be acknowledged; wording everywhere says it supplements the cane | SAFE-05, SAFE-06 | |
| H15 | No LiDAR, and the walker thinks steps are watched | older or non-Pro iPhone | High | Said out loud at Start and shown on screen | GUIDE-02 | |
| H16 | Both ears blocked | earphones | Medium | Single earpiece; other audio ducked, not stopped | OUT-09 | |
| H17 | Personal data leaks | cloud, analytics | Low | No network code; no data collected; nothing leaves the phone | SAFE-01, PRIV-01 | |
