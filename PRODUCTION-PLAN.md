# walker-jumpman — Production plan

Design revision: 0.2.0 · September 10, 2026 · **Draft; no implementation started**

**Later implementation record:** Bear's request to build a simple level authorized the first slice. [BUILD-REPORT.md](BUILD-REPORT.md) records its completed work and machine checks. This original plan is retained; no full-MVP ticket or human-review checkpoint is marked complete by implication.

Prepared under Bear's request to complete all design work. This authorizes this plan, not task execution, paid generation, or publication. [GDD](GDD.md) remains the requirements authority. [Design status](DESIGN-STATUS.json) keeps human gates pending.

## Build contract

The smallest first slice is: launch → move → jump → hit a hazard → respawn → reach a finish → replay. Use original geometric placeholders. No art API, account service, controller library, or online dependency is needed for this slice.

Use the new `games/walker-jumpman/godot/` child for the future runnable project. Set the Godot project display name to `walker-jumpman`. Preserve `../jumping-man-godot/` and all other recovered collections. Do not run the legacy publisher against an existing project.

All tasks below have status **PLANNED / NOT STARTED** unless marked DEFERRED. Proposed tracks: ENG engineering; ART presentation; CON content; OPS tooling and delivery. Human design approvals remain Bear's responsibility.

## Phase 1 — Foundation

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-001 | OPS / FEAT-08 | Human build/scope decision | Discover installed Godot, record exact version, proposed GDScript/Compatibility profile, export-template availability and disk budget | Toolchain record; no invented executable path; missing components reported before engine claims |
| WJ-002 | ENG / FEAT-08 | WJ-001 | Create isolated Godot project, main scene, input actions, named collision categories, non-destructive source-control exclusions | CASE-001; project name is walker-jumpman; recovered sources unchanged |
| WJ-003 | OPS / FEAT-08 | WJ-002 | Establish deterministic fixture harness and evidence record format | Failing fixture produces failure status; missing evidence never becomes PASS; no dependency on generated art |

## Phase 2 — Core loop skeleton

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-004 | ENG / FEAT-01 | WJ-002–003 | CharacterBody2D movement, collision, facing, 60-Hz tuning resource | CASE-002–003; parameters editable without changing level code |
| WJ-005 | ENG / FEAT-02 | WJ-004 | Single jump, ceiling response, coyote/buffer consumption | CASE-004–006; measured solver baseline stored |
| WJ-006 | ENG / FEAT-03 | WJ-004–005 | Session state owner, hazard/fall events, death/reset/retry, event precedence | CASE-009–011; missing animation does not block reset |
| WJ-007 | ENG / FEAT-04 | WJ-006 | Minimal start, explicit finish, replay and results in one greybox room | CASE-012–013; no relative scene-index arithmetic |
| WJ-008 | CON / PX-01, PX-02, PX-04 | WJ-007 | First playable human review and short real capture | Record a success and a failure/retry; record feedback, not a fun certification |

**Checkpoint:** inspect movement and retry before building the full course. If those fail, fix WJ-004–007; adding artwork is not the remedy.

## Phase 3 — Content pipeline and art foundation

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-009 | CON / FEAT-06 | WJ-008 reviewed | Convert the candidate level data into authored scene geometry | [Level design](LEVEL-DESIGN.md) constraints; visible landings and no unreachable required route |
| WJ-010 | ART / FEAT-06 | WJ-009 | Original player/terrain/hazard/cherry/finish placeholders with consistent silhouettes | [Asset plan](ASSET-PLAN.md); CASE-016; zero copied assets without records |
| WJ-011 | ENG / FEAT-05 | WJ-006, WJ-009–010 | Unique-ID cherries, attempt score and reset ownership | CASE-007–008 and CASE-011; exactly twenty; zero-cherry win possible |

## Phase 4 — Full MVP content and presentation

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-012 | CON / FEAT-06 | WJ-009, WJ-011 | Refine all three zones, direct route and optional collection opportunities | CASE-008, CASE-020–021; do not force incidental cherry collection on the main route |
| WJ-013 | ENG / FEAT-06 | WJ-012 | Camera bounds/look-ahead, resize-safe HUD, reset snap | CASE-003, CASE-016; no essential landing offscreen |
| WJ-014 | ENG / FEAT-07 | WJ-007, WJ-013 | Pause/settings, mute, remapping, safe focus loss, preference recovery | CASE-014–016; menus usable without a mouse |
| WJ-015 | ART / FEAT-06–07 | WJ-010, WJ-014 | Minimal feedback cues; optional locally created or rights-cleared effects | Muted play communicates every essential event; no paid calls; sounds never control state transitions |

## Phase 5 — End state resolution

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-016 | ENG / FEAT-03–05 | WJ-011, WJ-014–015 | Integrate results, complete reset matrix and stress duplicate events | CASE-007, CASE-009–015; 20 repeated retries and double-click replay stay coherent |
| WJ-017 | CON / PX-01–06 | WJ-012–016 | Run formative human sessions and inspect defects | [Playtest protocol](PLAYTEST-PLAN.md); actual observations and prioritized changes |
| WJ-018 | ENG/CON / affected features | WJ-017 | Apply authorized smallest revisions; rerun affected cases | Every changed requirement is versioned; prior failures retained; no weakened test masquerading as a fix |

## Phase 6 — Polish and platform

| Ticket | Track / feature | Dependencies | Work | Acceptance |
|---|---|---|---|---|
| WJ-019 | OPS / FEAT-08 | WJ-016–018 | Clean-import and frame/load/respawn measurements on recorded machine | CASE-001, CASE-010, CASE-018; numerical evidence, not estimates |
| WJ-020 | OPS / FEAT-08 | WJ-019 | Produce local Web export and serve it for testing | CASE-019 in named browser versions; actual input, audio/focus and routes tested |
| WJ-021 | ART/OPS / FEAT-08 | WJ-010, WJ-015, WJ-020 | Review asset records and actual package contents | CASE-022; no unknown-license assets, credentials, or private test notes shipped |
| WJ-022 | OPS / FEAT-08 | WJ-020–021 | Assemble local handoff: version/build IDs, source, instructions, test evidence, package checksums | Bear can open and play the verified local package; public release still requires explicit authorization |

## Deferred tasks — not release prerequisites

- WJ-D01 / FEAT-09: optional moving-platform detour; implement only after approval, then run CASE-017.
- WJ-D02 / FEAT-10: local personal best; write migration/corruption/reset rules before implementation.
- WJ-D03 / FEAT-11: decorative polish; retain readability and provenance.
- WJ-D04 / FEAT-12: optional assistance profile; involve affected players and distinguish assists from tested baseline behavior.

## Dependency map and failure handling

Foundation WJ-001–003 → controller WJ-004–005 → coherent session WJ-006–007 → human checkpoint WJ-008 → course/art/cherries WJ-009–011 → content/camera/settings/feedback WJ-012–015 → integration/review/revision WJ-016–018 → local acceptance and handoff WJ-019–022.

This is an implementation ordering, not a duration estimate. No staffing, finish date, or hours budget has been agreed. Stop a repair cycle if the same failure repeats without a new hypothesis, the engine is missing, or a change requires new scope/spend authority. Preserve the last working project; never overwrite it with a failing attempt or mark a blocked engine check as passed.

AI can do the authorized implementation and measurement. Human review is required at design tradeoffs, player-experience judgments, and release decisions; an unattended worker does not become a substitute reviewer.
