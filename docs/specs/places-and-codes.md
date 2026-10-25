# Spec: places and printed codes

**Code:** `Core/Sources/HomeStepCore/Place.swift`, `PlaceStore.swift`; `Sources/HomeStep/MarkerLayer.swift` (reads codes), `MarkerSheet.swift` (prints them).
**Tests:** `Core/Tests/HomeStepCoreTests/PlaceTests.swift`, `PlaceStoreTests.swift`, `StorageTests.swift`; `Tests/MarkerSheetTests.swift`.
**Requirements:** REQ-MARK-*, REQ-PLACE-*.

## Model

A **place** (a home, an office) has a name and a list of **landmarks**. A landmark has:

| Field | Meaning |
|---|---|
| `marker` | the number printed in its code, unique within the place |
| `name` | "Kitchen", "Living room" |
| `cue` | words to say instead of the name (optional) |
| `kind` | landmark, step down, step up, stairs, other hazard |
| `note` | where to tape the code, for the helper |

Every kind except a plain landmark is a hazard and plays as a warning.

### What is said

- With a cue: the cue. For a hazard, "Step down." / "Step up." / "Stairs." / "Caution." goes first, unless the cue already contains those words.
- Without a cue: the hazard words (if any), then the name with a full stop. "Step down. Living room."

## The code

A QR code holding `akshi:<n>` (the format's name from an earlier version of the app; any letter case), or a bare number, with n from 0 to 9999. Anything else, such as a web address, a Wi-Fi code or `akshi:` with no number, is ignored. The app prints `akshi:<n>`.

Codes are read with Vision's barcode detector on every camera frame, with the image oriented for an upright phone. A number the place in use doesn't have is ignored.

### Printed sheet

One US Letter page per landmark: the place name and number at the top, a 6-inch QR code with high error correction, the landmark's name, its kind (hazards in red), and where to tape it. Hazards say to tape a code about a stride before the hazard, on each side of a step.

## Storage

All places are kept in one file, `places.json`, in the app's Application Support folder:

```json
{
  "version": 1,
  "activePlaceID": "UUID or null",
  "places": [ { "id": "UUID", "name": "Home", "landmarks": [ { "id": "UUID", "marker": 1, "name": "Kitchen", "cue": "", "kind": "landmark", "note": "" } ] } ]
}
```

- Written atomically, with iOS file protection (readable after the phone is first unlocked).
- If the file can't be read, it is renamed `places.json.corrupt` (or `.corrupt-<time>` if that exists), no places are loaded, and the user is told.
- The first place added is put in use. Deleting the place in use leaves none in use.

## Sharing

A place is shared as a `.homestep` file:

```json
{ "format": "akshi.place", "version": 1, "place": { ...as above... } }
```

On import:

1. Try the `.homestep` shape; if that fails, try the first version's `home_map.json` (nodes keyed by number, each with `say`, `hazard`, `room`). If both fail, refuse it.
2. Give the place and every landmark new identities.
3. If two landmarks share a number, keep the number for the hazard and give the other the lowest free number.
4. Add it, but don't put it in use unless no place is in use.
