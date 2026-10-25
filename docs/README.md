# HomeStep documentation

How the pieces fit together:

```
PRD  ──►  requirements  ──►  specs  ──►  code
 why        what, numbered     how         Core/ and Sources/
             │
             ├──►  tests (cite requirement IDs)  ──►  traceability.md (generated)
             ├──►  field protocols (on the phone, at home)
             └──►  hazard analysis (what could hurt someone, and which requirements prevent it)
```

| Document | What it's for |
|---|---|
| [product/PRD.md](product/PRD.md) | The problem, who it's for, goals, non-goals, scope, how we know it works |
| [requirements.md](requirements.md) | Every requirement, numbered, with its reason and how it's verified |
| [specs/step-detector.md](specs/step-detector.md) | The step and obstacle detector: inputs, geometry, rules, measured behaviour, known issues |
| [specs/announcer.md](specs/announcer.md) | What is said, beeped and buzzed, and when |
| [specs/places-and-codes.md](specs/places-and-codes.md) | Places, landmarks, the QR code format, storage and sharing |
| [specs/guide-session.md](specs/guide-session.md) | Starting, stopping, stalls, interruptions, aim, "Where am I?" |
| [specs/test-recording.md](specs/test-recording.md) | The developer-mode test-walk log and its analysis |
| [safety/hazard-analysis.md](safety/hazard-analysis.md) | Hazards, causes, mitigations, what's left over |
| [testing/test-plan.md](testing/test-plan.md) | The five test levels, the inspection checklist, how to change a requirement |
| [testing/field-protocols.md](testing/field-protocols.md) | What has to be checked with the phone on the stick |
| [decisions.md](decisions.md) | Why it's built the way it is |
| [traceability.md](traceability.md) | Generated map from requirements to tests |

## Working on HomeStep

1. Start from a requirement. If the change needs a new one, add it to `requirements.md` first.
2. Write the test, citing the requirement (`// REQ-STEP-03`), and see it fail.
3. Change the code. Rules belong in `Core/`, where they can be tested without a phone; `Sources/HomeStep/` only connects them to ARKit, Vision, audio and the screen.
4. `make test`.
5. For anything that affects steps or obstacles, run the field protocol before anyone relies on it.
