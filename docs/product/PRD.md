# HomeStep: product requirements

**Status:** describes HomeStep 1.1.0 (2), the build installed and tested at home.
**Owner:** Sathvik Subramanian.

## 1. Problem

My grandfather is visually impaired; he has lost about ninety percent of his sight and walks with a black walking stick. At home he has three problems:

1. **He loses his way.** Some mornings he ends up at a console table he thinks is the kitchen counter.
2. **He can trip on steps.** Our living room is sunken, with one step down into it and one back up.
3. **He bumps into things.** Chairs, an ottoman, a door left half open.

He isn't alone. Around seven million Americans have vision loss that glasses can't fix, and about half of older adults with vision loss move around less because they are afraid of falling.

The tools he has don't cover this. Scene describers (Be My AI, Seeing AI) can say what's in a photo but don't know where he is. Venue apps (GoodMaps, NaviLens) map public buildings, not homes. A cane finds a step when the cane reaches it, which on a swinging cane is sometimes late.

## 2. Users

| User | Who | What they need |
|---|---|---|
| **Walker** | A visually impaired adult, often older, walking indoors with a cane | Warning before a step or obstacle; knowing which room they are in; never being misled by silence |
| **Helper** | A sighted family member | To mount and aim the phone, name the places, print and tape the codes, and check it works |
| **Tuner** | Whoever sets the app up for a particular house (often the helper) | To see what the app sees and adjust when it speaks |

## 3. Goals

- **G1. Warn about steps before the walker reaches them,** down and up, with no setup and no codes.
- **G2. Warn about obstacles** in the walking path, more urgently as they get closer.
- **G3. Tell the walker where they are** from printed codes placed by doorways.
- **G4. Let anyone set up their own place** without a programmer.
- **G5. Never mislead.** Silence must never be the only sign that the way is clear, and the app must say so when it stops working.
- **G6. Keep everything on the phone.** No accounts, no network, nothing leaves the phone.

## 4. Non-goals

- **Replacing the cane, a guide dog or people.** HomeStep is an extra warning.
- **Outdoor or street navigation.**
- **General scene description or text reading.** Apple Magnifier and Be My AI already do this well.
- **Turn-by-turn routing between rooms** (a later version, see section 8).
- **Emergency use.**

## 5. How it is used

1. A helper clamps the phone about halfway up the walking stick, upright, rear camera facing forward and down.
2. In the app they add a place ("Home"), add a landmark for each spot (Kitchen, Front door, Living room step), print the codes and tape each one about a stride before its spot, low on a wall or door frame. A step gets a code on each side.
3. The walker presses Start. HomeStep says "Guiding." Then, while they walk:
   - clear floor: "Proceed." every couple of seconds;
   - a step coming: a fast double beep, then "Step down." or "Step up.";
   - an obstacle: a low beep that speeds up, and "Obstacle ahead.";
   - a code: its name, like "Kitchen.";
   - a problem: "Cannot see the floor. Tilt the phone down." or "Guidance stopped. Use your cane."
4. "Where am I?" (a button, or the iPhone's Action button) repeats the last place read.

## 6. Scope of this release

| Area | In 1.1.0 |
|---|---|
| Step down / step up detection (LiDAR) | Yes |
| Obstacle detection (LiDAR) | Yes |
| Printed codes for places and hazards | Yes |
| Several places, sharing a place as a file | Yes |
| Onboarding with a safety page | Yes |
| "Where am I?" and the Action button | Yes |
| Settings: speech, tones, vibration, rate, warn distance | Yes |
| Developer mode: live numbers, test-walk recorder, MARK WRONG | Yes |
| "See what HomeStep sees" | Yes |
| iPhones without LiDAR | Codes only, and it says so |
| Network, accounts, AI assistant | No |

## 7. How we know it works

| Measure | Target | Evidence |
|---|---|---|
| Steps caught on the approach | Every approach, both directions, with time to stop | Field protocol FP-1 (formal 10 + 10 + 10 trial) is **not yet run**; informal walks and the ten-scene test caught every step |
| False step warnings on flat floor | None during normal walking | Logged walk: flat-floor noise about 0.005 m against a 0.07 m threshold; scenario tests |
| Codes read and spoken | Each code, from a stride away | FP-3 |
| Silent failure | Never | Requirements REQ-SAFE-04, REQ-GUIDE-04, tested in the core |
| Data leaving the phone | None | No network code; privacy manifest declares no data collected |

## 8. Later

- AI that describes the room out loud, on request, without slowing the step warning.
- Directions between rooms ("take me to the kitchen").
- AprilTag codes, which read from further away and at sharper angles than QR codes.
- An easy way to call family.
- Sensors built into the stick itself, so it doesn't need a phone.

## 9. Risks

The main risks are a missed step, warnings so frequent the walker stops listening, and the app failing quietly. They are analysed in [`../safety/hazard-analysis.md`](../safety/hazard-analysis.md).
