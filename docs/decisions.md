# Design decisions

Short records of the choices that shaped HomeStep, newest last. Each says what was decided, why, and what it cost.

## D1. The app supplements the cane; it never replaces it
**Decided:** June 2026, before any code. **Why:** the cane is reliable and the walker trusts it; an app on a phone can miss things. **Cost:** every feature is judged by whether it could tempt someone to leave the cane behind. See REQ-SAFE-05, -06.

## D2. The phone rides on the walking stick
**Why:** the camera has to see the floor right where the stick is going, and the walker already carries the stick everywhere. **Cost:** the phone swings with the stick, which shaped the whole detector (D4, D5). The mount covers the bottom of the screen, so all controls are in the top half.

## D3. Everything on the phone, no network
**Why:** a warning that depends on a connection can be late or missing, and nothing about a person's home should leave their phone. An early version had an on-demand AI assistant through a cloud service; it never worked end to end and was taken out. **Cost:** no AI description of the scene for now. See REQ-SAFE-01, REQ-PRIV-01.

## D4. Measure height in the gravity-aligned world, not distance along a ray
**Why:** the first detector watched how far a downward ray reached and warned when that distance jumped. On a swinging stick, the swing alone changed the distance by more than a whole step. ARKit's world knows which way is down, so each depth point becomes a height that tilting doesn't change. See REQ-STEP-01.

## D5. Compare two strips of floor from the same frame
**Why:** comparing the floor ahead with a floor height remembered over the last second picked up ARKit's position wobble (a couple of centimetres while walking) as fake drops. Reading both from one frame cancels it. Recorded walks then showed about 0.005 m of noise on flat floor against a 0.07 m threshold. See REQ-STEP-02.

## D6. One probe strip, no look-ahead band
**Why:** with a separate band further out, a chair hiding the floor behind it looked like a drop. **Cost:** the warning comes from about 0.7 m out instead of a stride further; the warn distance is adjustable to compensate.

## D7. Coverage tests; much stricter for step up than step down
**Why:** a sweep often shows only part of an edge in a frame. Asking what share of the strip is low catches a partial edge without firing on scattered noise. A step up lifts the whole floor while a chair seat lifts a patch, so step up needs 60% against 15% for step down. Missing a step down is the worse error.

## D8. Thresholds come from recorded walks
**Why:** the false warnings during normal walking only went away once a recorder (developer mode) and a MARK WRONG button produced data. A threshold change needs a recorded walk behind it. See REQ-LOG-*.

## D9. Silence never means "clear"
**Why:** to someone who can't see the screen, a stopped app sounds exactly like a clear path. So "Proceed" repeats while walking, Start is always answered, and every failure is said out loud. See REQ-SAFE-04, REQ-CLEAR-*.

## D10. Codes, not maps, for "where am I"
**Why:** a printed code by a doorway is cheap, works in any house and can't drift. **Cost:** the walker has to pass close to a code. AprilTags, which read from further away, are the planned upgrade.

## D11. Users set up their own places
**Decided:** September 2026. **Why:** the first version had our house built in; anyone else would need a programmer. Now a helper adds places and landmarks in the app and prints the codes. The original codes (bare numbers) and house map still work.

## D12. Decision logic in a package tested without a phone
**Decided:** October 2026 (this branch). **Why:** the rules that keep someone from falling were only testable by walking at the step. Moving them into `HomeStepCore`, with a synthetic room that renders LiDAR depth, lets every rule run in seconds on any Mac. The rendered walks found KI-1. **Cost:** a second module and a thin adapter in the app. A side-by-side review found no change in behaviour from the phone build; the field protocols still have the final word.
