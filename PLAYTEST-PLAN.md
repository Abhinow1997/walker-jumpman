# walker-jumpman — Playtest and inspection plan

Design revision: 0.2.0 · **All tests unrun; this is a protocol.**
The authoritative requirements and CASE-001–022 are in [the GDD](GDD.md#appendix-b-acceptance-and-playtest-matrix).

## Before the first run

Record exact Godot version, renderer, physics rate, machine/OS, logical and display resolution, input devices, design revision, source/build identity, and whether this is editor play or an exported build. If no Git commit exists, record a reproducible source snapshot hash; never invent one.

Use the same tuning resource in fixtures and the game. Label desktop and Web evidence separately. Record any unsupported target as untested, not passing by analogy.

## Mechanical test sequence

1. CASE-001 first: import/start failure blocks behavior tests.
2. CASE-002–006: controller and timing before course adjustments.
3. CASE-009–011: death/reset and event precedence before scoring.
4. CASE-007–008, CASE-012–016: collection, finish, UI and route integration.
5. CASE-018: performance with settings/conditions recorded.
6. CASE-019: actual export, not the editor running the same source.
7. CASE-022: provenance and package contents before distribution.

CASE-017 is explicitly deferred with moving platforms. CASE-020–021 are human sessions, never filled by simulated agents.

## Useful fixtures

- Flat floor with a wall, visible coordinate grid, and unobstructed jump space.
- Low ceiling, ledge, and landing fixtures for takeoff/buffer/ceiling cases.
- Two overlapping hazard triggers, overlapping goal/pickup, and repeated callbacks in different orders.
- Reset loop fixture with a missing animation and a corrupt preferences file.
- Export opening fixture testing start focus, menu activation, mute, resize, and restart.

Fixture output should include configured and observed quantities. Capture controller position/velocity by physics tick; rendering frame caps are a test variable, not a physics timestep. These fixtures have not yet been written.

## Human sessions: formative, not research-grade validation

Aim for five voluntary sessions: three less-experienced and two experienced platformer players. If fewer are available, record the actual sample and its limitation. Do not invent participant observations. Obtain permission before recording voice/video; avoid names and unnecessary personal details.

Suggested sequence:

1. Explain that the game, not the person, is being evaluated. Explain recording, if any.
2. Say: “Start the game and try to reach the end. You may stop whenever you want.”
3. Observe the first attempt without coaching. Record pauses, mistaken controls, deaths, route choices, and spontaneous comments.
4. After a failure, ask neutrally: “What do you think happened?” Do not tell them the intended answer.
5. After completion or stopping: “What counted as winning?” “What were the cherries for?” “Was there a point where you did not know what to do?”
6. Offer, but do not require, another attempt. Record whether they choose one and what they change.
7. For willing participants, repeat a short section muted and using keyboard-only menu navigation.

Do not tell players that retries should be enjoyable. A leading question can manufacture apparent support for the design. “Would you play again?” is weaker evidence than a voluntary replay, and neither proves broad appeal.

## Observation sheet

Use one row per incident, not one summary adjective per participant.

| Field | Record |
|---|---|
| Session | Anonymous ID, date, permission status |
| Build | Exact design and build identity, engine, desktop/Web |
| Context | Experience category, settings, zone and attempt |
| Observation | What the player actually did or said |
| Requirement | PX, MECH, FEAT and CASE IDs where applicable |
| Interpretation | Hypothesis about cause, clearly separate from observation |
| Severity | Blocks completion / repeated confusion / minor friction |
| Proposed next check | Small test or change, not an automatic redesign |

Keep empty forms empty until used. A lack of complaints is not proof of accessibility or comprehension.

## Failure report and revision loop

Every issue needs: ID, build/design versions, repro steps, expected versus actual result, evidence path, severity, likely owner, and status. A screenshot shows layout; a replay/log shows event sequence; neither alone establishes player experience.

Distinguish:
- Implementation defect: the game contradicts the agreed requirement.
- Design hypothesis failure: it behaves as specified but people cannot understand or enjoy it.
- Tool/environment blocker: Godot, export templates, or browser capabilities are unavailable.
- Evidence gap: no test has actually exercised the claim.

Fix implementation defects against the existing spec. For design changes, propose the new behavior and its consequences, obtain appropriate human review, update the revision, then rerun affected cases. Never “fix” a failed test by silently lowering its threshold.

## Evidence naming and truth conditions

Proposed records belong under the game project's evidence area when runs exist. Use a unique run ID, not an overwritten `latest-pass` file. Record status as NOT_RUN, PASS, FAIL, or BLOCKED and preserve previous failures.

Minimal future result shape:

```json
{
  "case_id": "CASE-005",
  "design_version": "0.2.0",
  "build_id": null,
  "engine_version": null,
  "status": "NOT_RUN",
  "observed": null,
  "evidence_paths": [],
  "reviewer": null
}
```

A future checker must reject PASS when build identity, observation, or required evidence is missing. Human-experience cases require human observations; an agent cannot auto-sign them.

## Export review checklist

- Imported from source without relying on a local cache.
- Correct local package actually launched through a server.
- Zero-cherry and all-cherry runs possible in the exported version.
- Menus, mute, focus loss, resize and replay work.
- Browser/engine errors inspected and documented.
- Asset records match actual shipped contents.
- Local file hashes and concise play instructions included.
- Publication approval recorded separately before any upload.

A 15–20 second real clip may demonstrate the central loop, but is not a substitute for this evidence.
