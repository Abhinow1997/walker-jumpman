# walker-jumpman — Detailed Game Design Document

> **Draft 0.2.0 · September 10, 2026 · Human review pending**
>
> A Godot-focused design for Walker's **Game brief → Build → Playtest → Inspect → Revise → Export** workflow. This is a specification, not a playable build or a test report.

**Runtime update, September 10:** Bear subsequently requested a simple level. The separate [First Steps build report](BUILD-REPORT.md) records the implemented control/retry slice and actual tests. Historical “not built/not run” statements below describe this full design draft; they do not override that later evidence. Full-MVP acceptance and human design/playtest signatures remain open.

[Game brief](GAME-BRIEF.md) · [Design status](DESIGN-STATUS.json) · [Design package](README.md) · [Zelda workflow](../../docs/zelda-gdd-workflow.md)

## 1. Metadata and decision status

| Field | Value |
|---|---|
| Project name / project ID | walker-jumpman / walker-jumpman |
| Design revision | 0.2.0 |
| Human design owner | Bear; approval pending |
| Drafting contribution | AI-assisted source inspection, design synthesis, Godot reference checks, and test specification |
| Game type | Small single-player 2D precision-lite platformer |
| Proposed implementation | Godot 4, typed GDScript, Compatibility renderer |
| First review target | Local desktop play on Bear's Mac |
| Proposed distributable | Locally served Web export; public hosting is separate |
| Runtime implementation / tests / export | Not built / not run / not produced |
| Educational track | Inactive |
| Production task document | [Production plan](PRODUCTION-PLAN.md) drafted under the request to complete all design work; no tasks executed |

**Evidence vocabulary:** “Observed” means present in the recovered files, not witnessed in a running game. “Proposed” means a draft requirement. “Approved” requires a human record. “Implemented” requires actual project files. “Verified” requires recorded results for the relevant build and design revision. Every gameplay requirement below is proposed unless explicitly identified as a source observation.

Bear has specified that every new project name starts with `walker-`; the first example is `walker-jumpman`. That naming decision is confirmed. The source collection remains separately named `jumping-man-godot` and is not renamed.

The user requested a detailed draft; that authorizes writing with visible assumptions, not signing the four Zelda gates. Vision, systems, world, and scope approvals remain pending. The exact Godot version, renderer availability, reference machine, export templates, and browser versions must be recorded before implementation testing.

The existing engine guide describes C#/.NET. This document proposes a GDScript profile for this pilot; it does not silently override that guide or claim that Walker's publisher already supports this profile.

## 2. Vision summary

**Logline:** Guide a nimble runner through a compact obstacle course, choosing safe landings or tempting cherry detours, learning from readable mistakes through immediate retries toward a satisfying finish.

**Player fantasy:** “I am becoming the person who can see the jump before taking it.” The fantasy is growing competence, not controlling a superhero with an expanding move list.

**Player:** someone seeking a short keyboard-controlled challenge. Prior platformer familiarity is useful but not assumed in onboarding. The audience hypothesis must be tested with newcomers as well as experienced players.

**The promise:** each attempt gives the player a legible decision and useful feedback. The next attempt should improve because the player understands something, not because a random obstacle rolled differently.

**The whole game:** start, traverse one level, optionally collect cherries, reach the finish, inspect the result, replay or leave. There is no subscription, account, server, combat, required grinding, or metagame.

The biggest unresolved design question is whether the proposed movement and course make failure feel informative rather than fiddly. That is answered in a greybox with humans, not with more narrative or polished art.

## 3. Design pillars

| ID / pillar | Experience protected | Honors it | Violates it | Failure if ignored |
|---|---|---|---|---|
| PILLAR-01 — Read the landing | Understand the next decision before committing | Visible destination and clear collision surfaces | A mandatory blind leap | Failure feels arbitrary |
| PILLAR-02 — Earn another try | Want to retry because the error is understandable | Rapid, predictable reset | Long death screens or a lives tax | The player quits before learning |
| PILLAR-03 — Choose the risk | Decide how demanding the run should be | Optional cherry detours | Requiring every cherry to unlock the finish | Collection becomes compulsory busywork |
| PILLAR-04 — Small, complete game | Experience a coherent beginning, challenge, and end | One finished course with replay | Many half-implemented mechanics | A demo menu replaces an actual game |

**Collision rule:** readability outranks decorative spectacle; reliable control outranks novelty; completing the small course outranks adding a new system. Retry speed does not justify hiding what killed the player. Optional challenge must not compromise an accessible direct route.

## 4. Core loop

**Micro, about 2–10 seconds:** observe a landing → choose takeoff/route → move and jump → receive collision or collection feedback → land, fail, or approach the next decision.

The risk is losing the current attempt's position and cherries. The reward is a successful landing, a cherry, and more confident control. Every landing must leave a sensible next action.

**Meso, a level attempt:** leave the safe start → cross three increasingly combined zones → choose optional collection risks → reach the finish or retry. First successful completion is provisionally targeted at 2–4 minutes for a new player, including retries; this is a pacing hypothesis, not a required runtime.

**Macro, a short session:** finish once → choose a cleaner run or a higher cherry total → stop with a complete result. Persistent unlocks and daily retention mechanics are out of scope.

**Loop honesty test:** remove the character art, background, sound, and cherries. Moving through the greybox still needs to provide understandable, satisfying decisions. If it does not, improve movement and layout before producing final art.

There is no scheduled reward for waiting, no randomized success, and no requirement to repeat a solved section solely to accumulate currency.

## 5. Player Experience Goals

| ID | Testable experience hypothesis | Mechanic / section | How to evaluate it |
|---|---|---|---|
| PX-01 | The player feels in control when a planned jump lands where expected | MECH-01, MECH-02; §6 | CASE-002–006 plus human CASE-020 |
| PX-02 | The player understands a mistake when a hazard or missed landing ends an attempt | MECH-04; §§6, 8 | CASE-009–011; player explains cause in CASE-020 |
| PX-03 | The player feels ownership when choosing a cherry detour or bypassing it | MECH-03; §§6, 8 | CASE-007–008; route choice in CASE-021 |
| PX-04 | The player wants another attempt when control returns quickly after failure | MECH-04; §7 | CASE-010; observed voluntary retries in CASE-020 |
| PX-05 | The player feels closure when the finish reports the run and offers replay | MECH-06; §§7, 10 | CASE-012–013; human completion interpretation |
| PX-06 | The player can read and operate the game without relying on sound or color alone | MECH-07; §§7, 14 | CASE-014–016; keyboard/muted play in CASE-021 |

These are hypotheses, not promises that every person will feel the same emotion. Automated tests measure behavior; human sessions evaluate experience. A feature that serves none of these goals must justify its existence before entering scope.

## 6. Mechanics and behavioral requirements

### MECH-01 — Move and stop

**Purpose:** let the player position a takeoff and correct a landing. Serves PX-01 and PILLAR-01.

**Input:** move_left and move_right. Simultaneous left/right produces neutral intent, not alternating priority. Use action mappings, not hard-coded physical keys throughout scripts.

**Rule:** accelerate toward a horizontal speed cap; decelerate toward zero when intent is neutral. Ground and air use the same initial tuning so the first prototype is easy to reason about. Facing direction follows the last nonzero input. No sprint or dash.

**Output:** visible movement and idle/run pose; actual collision position is authoritative. Animation never changes collision size.

**Edges:** both directions held; reversal at a ledge; wall contact at full speed; focus loss while holding movement. After regaining focus, gameplay remains paused until the player resumes. See CASE-002–003 and CASE-014.

**Boundary:** ramps, ice, knockback, ladders, swimming, and alternate movement modes are excluded.

### MECH-02 — Jump with modest forgiveness

**Purpose:** turn a visible landing into an executable decision. Serves PX-01 and PX-02.

**Rule:** one fixed-strength jump on a fresh press while grounded, or within the coyote window after leaving a floor. A jump press shortly before landing is buffered once. Both windows start at six 60-Hz physics ticks (100 ms); age of six ticks is accepted, seven is expired. A jump consumes the eligibility and buffer immediately. Holding jump cannot auto-bounce. There is no variable-height, double, or wall jump in this revision.

**State:** grounded / rising / falling; jump request age; ticks since valid floor contact; whether the floor opportunity has already been consumed. Update eligibility with care around the takeoff tick so stale floor contact cannot grant a second jump.

**Output:** upward velocity, jump pose, optional sound with a visual equivalent. Gravity and collision determine the rest; touching a ceiling cancels upward travel without granting another jump.

**Edges:** press just inside/outside coyote window; press before landing; hold across landing; repress in midair; hit a low ceiling; die with a buffered press. Reset clears jump buffers and requires a fresh jump press. CASE-004–006 and CASE-010 cover these.

**Initial tuning hypotheses — logical pixels, not Unity units:**

| Parameter | Proposed start | Reason / test |
|---|---|---|
| Physics rate | 60 ticks/s | Common timing basis for the pilot |
| Horizontal speed cap | 160 px/s | Allows course reading within the viewport |
| Acceleration / deceleration | 1,280 / 1,920 px/s² | About 0.125 s to full speed; prompt stopping |
| Jump launch velocity | -320 px/s | Negative Y is upward in the proposed 2D coordinates |
| Downward gravity | 960 px/s² | Fixed-height baseline |
| Fall-speed cap | 480 px/s | Bound high-speed collision tests |
| Coyote / buffer | 6 / 6 physics ticks | Small input forgiveness, measured explicitly |
| Player body | 18 × 28 px collision box | Stable greybox body; art may be 32 × 32 |
| Terrain unit | 16 px | Level-layout planning grid |

**Ballistic sanity check, not a gameplay result:** ignoring discrete integration, ceilings, the fall cap, and input forgiveness, apex time is 320/960 ≈ 0.333 s; rise is 320²/(2×960) ≈ 53.3 px; same-height flight time is about 0.667 s. At an already attained horizontal speed of 160 px/s, travel is about 106.7 px. Acceleration, takeoff position, and collider geometry reduce practical margins.

Start required gaps at 32–64 px and rises at no more than 32 px. Verify every actual jump; theoretical range is not permission to build mandatory jumps at the limit. Optional same-height gaps may approach 80 px only after human testing. Coyote jumps must never be required to clear the main route.

### MECH-03 — Collect optional cherries

**Purpose:** create a visible risk choice and a replay goal. Serves PX-03 and PX-05.

**Rule:** twenty individually identified cherries per level attempt. A live player's overlap consumes one available cherry exactly once and increments the attempt counter. Collection is optional: zero cherries still permits completion.

**State / output:** available or consumed per stable cherry ID; HUD shows collected/20. Consumption has a short visual cue and optional sound. Cherries are not currency, health, or a gate key.

**Edges:** multiple signals for one overlap must award once; two different cherries in one tick award twice; a death resets all cherries and the attempt total; a reset during a collection callback must not leak a deferred award; a cherry overlapping a fatal hazard on the same tick is not awarded. CASE-007–008 and CASE-011 cover these.

**Boundary:** no inventory, spending, multi-level banking, persistent cherry totals, or mandatory collection.

### MECH-04 — Fail, understand, retry

**Purpose:** make mistakes informative without charging the player time unnecessarily. Serves PX-02 and PX-04.

**Rule:** touching a hazard or crossing the level's fall boundary ends the attempt once. Freeze player control, show a short readable failure cue, then reset the same level automatically. Target controllable respawn within one second of death on the reference machine, including the cue. Animation completion must not be a prerequisite for reset.

**Reset:** spawn position, velocity, buffered input, cherry state/count, attempt timer, and dynamic obstacle phase return to their initial values. Death count increments once and persists across automatic retries in that session. A manual restart resets the attempt without counting as a death. Replay from results or a new Start resets the session death count.

**Edges:** two hazards signal together; falling while a death transition is active; restart during respawn; a missing death animation; a held jump at spawn; spawn overlapping terrain. Invalid spawn geometry is a build defect, not a player challenge. CASE-009–011 cover these.

**Boundary:** no lives, checkpoints, health bars, loss of persistent currency, or random respawn.

### MECH-05 — Ride a moving platform (follow-up, not MVP-blocking)

**Purpose:** introduce a timing decision after stationary jumps are already enjoyable. Serves PX-01 and PX-03.

**Rule:** a platform moves horizontally between two endpoints at a proposed 48 px/s, reversing without teleporting. Standing on it carries the player; walking off and jumping detach cleanly. Initial design adds no launch boost on leaving. It may appear only on a later optional route; the first release route does not depend on it.

**Edges:** reversal while occupied; stepping off the edge; jump during reversal; invalid/identical endpoints; platform reset while the player dies. Invalid paths fail validation or remain safely stationary with a diagnostic, never divide by zero or index past a list. CASE-017 is deferred until this feature is authorized.

**Godot direction:** use an AnimatableBody2D and deliberate CharacterBody2D platform-follow behavior; do not transplant Unity transform-parenting code literally. Confirm behavior in the pinned engine. [Official CharacterBody2D reference](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)

**Boundary:** no vertical crush routes, rotating platforms, conveyors, or platform-velocity launch puzzles.

### MECH-06 — Finish and replay

**Purpose:** make success unmistakable and the next choice voluntary. Serves PX-05.

**Rule:** a live player touching the visible finish enters Completed exactly once. Freeze the run and display “Course complete,” cherries collected, and session deaths. Offer Replay and Main Menu. Finishing requires no minimum cherries.

**Edges:** repeated finish overlaps; finish and death in the same physics tick; replay clicked twice; missing next scene. Use explicit scene references; do not reproduce relative Unity build-index arithmetic. CASE-011–013 cover these.

**Boundary:** no surprise next level, ranked leaderboard, or mandatory credits wait.

### MECH-07 — Pause and understand controls

**Purpose:** give the player control over participation and presentation. Serves PX-06 and PX-04.

**Rule:** gameplay pause opens a keyboard-navigable menu with Resume, Restart attempt, Settings, and Main Menu. Leaving an active attempt requires confirmation; confirming Restart performs exactly one reset. Settings expose mute and keyboard action remapping, with conflict feedback and restore-defaults.

**Edges:** pause during death/completion; focus loss; rebinding a key already in use; restoring defaults; losing focus while a modal is open. Pause requests during death/completion do not replace those transitions. Closing a modal restores prior focus. A denied/unavailable settings save must leave the current session usable and report nonfatal feedback. CASE-014–016 cover these.

**Boundary:** no in-game console, account settings, or cloud synchronization.

## 7. Systems, ownership, and state transitions

### Session state machine

MainMenu → Playing → Completed → MainMenu or a fresh Playing session.
Playing → Dying → Respawning → Playing.
Playing ↔ Paused.
Focus loss during Playing → Paused; focus gain alone never resumes.

Only Playing accepts gameplay triggers. Resolve queued trigger events once per physics tick in this order: fatal event; otherwise completion (including valid same-tick cherries); otherwise collection. A fatal event suppresses completion and collection for that tick. Clear pending events when transitioning or resetting.

The level/session controller owns transitions, counter reset, replay, and level instantiation. The player emits intent/events; it does not load arbitrary scenes. A cherry cannot own the global score. The HUD observes state; it does not decide whether an award is valid.

| State | Gameplay physics / input | UI | Exit requirement |
|---|---|---|---|
| MainMenu | Off | Start, Settings, Quit where appropriate | Explicit Start |
| Playing | On | HUD, controls hint | Event or pause request |
| Paused | Frozen, including attempt timer and platforms | Pause/menu navigation remains active | Explicit Resume or confirmed action |
| Dying | Player disabled, duplicate death ignored | Brief failure cue | Bounded reset timer, independent of animation |
| Respawning | Disabled until scene reset is coherent | Transition cue | Valid spawn, cleared event queue, ready level |
| Completed | Run frozen | Results, Replay, Main Menu | Explicit selection |

Godot's scene pause and process modes must be configured so menus remain operable while gameplay pauses. Test timers, signals, and audio rather than assuming a paused tree handles every node correctly. [Official pause documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html)

### Persistence and observability

Persist only local preferences in the MVP: mute and key bindings. Do not persist partial attempts, cherry counts, or best times. If a settings file is corrupt, use defaults and preserve usability. Store runtime preferences outside source-controlled game content.

For development tests, record attempt number, event type, physics tick, position, and relevant state. Human test notes use anonymous participant labels, not personal data. No analytics service or external telemetry is included.

**Dependency warning:** a movement change can invalidate every jump, camera anticipation, hazard spacing, and platform test. A reset change can invalidate score, timers, and replay. Document affected tests in each revision.

## 8. Progression and level plan

The first level is three connected zones, approximately three 640-px viewport widths in the initial greybox. Geometry is a design proposal, not a recovered layout.

| Zone | Main action / intended teaching | Cherries | Risk and safeguard |
|---|---|---:|---|
| 1 — Practice Yard | Walk, stop, jump one low ledge; see a cherry and finish-direction cue | 4 | Initial flat area is safe; early misses land on recoverable ground |
| 2 — Cherry Run | Choose direct, broad landings or a more demanding cherry detour | 6 | Optional risk is visible before commitment; both routes reconnect |
| 3 — Home Stretch | Combine already introduced jumps and stationary hazards | 10 | No new mandatory mechanic; finish and last landing are visible |

**Skill curve:** position → jump → choose → combine. There are no resource upgrades. Challenge increases through spacing and route choice, not secretly changing movement parameters.

Required surfaces must be readable at the gameplay camera scale. Every mandatory landing is visible before takeoff; do not place a first-time hazard beyond the camera's view. Provide safe standing room before the final sequence.

**Content validation:** exactly twenty unique cherries; valid start and finish; no mandatory gap exceeding the reviewed jump envelope; no required cherry gate; no spawn/hazard overlap; no unreachable mandatory platform. Test both a zero-cherry completion and the all-cherry route. The latter must be possible without exploiting coyote timing.

**Drop-off risk:** repeated full-level restarts may feel tedious even in a short course. First response is to shorten solved traversal and reduce unfair spacing. Checkpoints require a new scope decision rather than being silently added.

**Replay value:** a better route and cleaner execution. Do not add grind, random rewards, or an artificial wait to lengthen the session.

## 9. World as a design artifact

The world is a compact, deliberately constructed practice course, not a simulation.

- Gravity pulls downward; solid surfaces support the player; decorative backgrounds never collide.
- Stationary hazards have a consistent dangerous silhouette and visible boundary.
- Cherries occupy navigable space and communicate an optional route, not a new physical law.
- The finish has a unique marker distinct from collectible shapes.
- No factions, crafting resources, destructible world, or social simulation are needed.

Visual direction is provisionally simple, bright pixel-scale shapes with strong separation between player, terrain, collectibles, and hazards. A neutral background must not camouflage a landing. Start with original greybox shapes; recover or commission art only after provenance is recorded.

The player may choose a risky route, but cannot break solid terrain, wall-climb, or acquire hidden abilities. Those constraints should remain true across art revisions.

## 10. Narrative delivery

There is no mandatory exposition or dialogue. The playable story is: “I entered, misjudged a jump, learned, chose a risk, and reached the end.”

| Beat | Delivery mechanic | Experience |
|---|---|---|
| Invitation | Safe start and concise controls | PX-01, PX-06 |
| Temptation | Visible cherry detour | PX-03 |
| Setback | Readable hazard with fast retry | PX-02, PX-04 |
| Resolution | Finish and results | PX-05 |

Narrative anti-goals: no cutscene before control; no lore required to understand a hazard; no story excuse for inconsistent mechanics. Branching narrative is not applicable because there are no narrative choices or consequential story states.

## 11. Characters and roles

**Runner:** the only controllable character. Gives the player an expressive, legible body and a stable collision reference. Removing it would remove both control and visual feedback. Idle/run/rise/fall/death states must agree with actual motion; animation cannot delay input or respawn.

**Hazards:** environmental objects, not thinking enemies. Their role is to mark consequences clearly. No AI behavior is implied by the availability of monster-like artwork.

**NPCs / character web:** not applicable. No named cast, dialogue system, relationship simulation, or quest-giver is required. Do not invent them to complete this section.

## 12. Feature priorities and MVP boundary

All feature states are **proposed; approval pending; not implemented; unverified**.

| Feature ID | Feature | Priority | Goal / dependency |
|---|---|---|---|
| FEAT-01 | Horizontal control and stable collision | CORE | PX-01; engine project |
| FEAT-02 | Single jump with bounded forgiveness | CORE | PX-01, PX-02; FEAT-01 |
| FEAT-03 | Hazards, fall boundary, reliable retry | CORE | PX-02, PX-04; FEAT-01–02 |
| FEAT-04 | Start, finish, results, replay | CORE | PX-05; coherent session state |
| FEAT-05 | Twenty optional cherries | CORE | PX-03, PX-05; FEAT-03–04 reset rules |
| FEAT-06 | Three-zone course, camera, legible HUD | CORE | PX-01–03, PX-06; FEAT-01–05 |
| FEAT-07 | Pause, mute, keyboard remapping and focus safety | CORE | PX-04, PX-06; session state |
| FEAT-08 | Reproducible local project and tested Web export | CORE | PX-06; FEAT-01–07 |
| FEAT-09 | Horizontal moving-platform detour | IMPORTANT | PX-01, PX-03; accepted base movement |
| FEAT-10 | Persistent personal best result | NICE-TO-HAVE | PX-05; explicit save-design decision |
| FEAT-11 | Decorative animation/background polish | NICE-TO-HAVE | PX-01, PX-05; rights-cleared assets |
| FEAT-12 | Optional assisted movement profile | EXPERIMENTAL | PX-04, PX-06; human accessibility testing |

**Scope warning:** 8 of 12 listed features are CORE (66.7%). This exceeds Zelda's default 40% warning. The count includes foundational delivery requirements and is not an effort estimate. Do not add optional items to dilute it. Before build approval, Bear should accept this compact boundary or choose a smaller experiment; no release deadline has been promised or extended.

**Complete MVP:** one course can be started, failed, retried, completed without cherries, completed with all cherries, replayed, operated while muted, and played from a locally served export. FEAT-09–12 are not prerequisites. Greybox assets can satisfy the MVP if legible and original.

**First build slice, not the whole MVP:** one room, movement, jump, one hazard, automatic retry, and a finish. This proves the control/reset cycle before content work. Completing that slice must not be reported as completing FEAT-01–08.

## 13. Out of scope — the record of “no”

Draft exclusions entered September 10, 2026; human decision owner: Bear; confirmation pending.

| Item | Reason | Reopen condition |
|---|---|---|
| Double/wall jump, dash, grappling | Changes the movement contract and level grammar | Base game tested and a distinct player benefit approved |
| Checkpoints or multiple levels | Adds progression/reset complexity | Evidence that the short course cannot support fair retries |
| Combat, enemies, bosses | Different core loop | Separate design brief |
| Crafting, inventory, currencies | No player-experience goal needs them | Separate design brief |
| Multiplayer, accounts, leaderboards, telemetry | Unnecessary services and operational scope | Explicitly approved online design |
| Procedural levels | Makes authored fairness harder to establish | Stable mechanics plus a separately tested generator |
| Mobile/touch or console release | Additional controls, testing, and packaging | Named target platform and budget |
| Story campaign, branching dialogue | No role in the present loop | New narrative goal tied to mechanics |
| Paid generation during greybox | Control hypotheses do not require generated art | Specific approved asset request and spend |
| Publishing anywhere | Local export is the current delivery boundary | Explicit destination and release authorization |

Windows/Linux native packaging is not a promised MVP target; Web testing is not evidence that native packages work. Controller support may be considered later; keyboard accessibility is part of the MVP now.

## 14. Technical, asset, and Walker production design

### Engine and scene responsibilities

Pin the installed Godot 4 version and matching export templates when implementation begins. Proposed game code is typed GDScript. Use a CharacterBody2D player with physics-step movement, and Area2D triggers for pickups and finish detection. CharacterBody2D exposes movement and floor/wall collision information suited to this controller. [Official class reference](https://docs.godotengine.org/en/stable/classes/class_characterbody2d.html)

Proposed scene structure below is **not yet present on disk**:

```text
godot/project.godot
godot/game/main.tscn                 # session owner, explicit state transitions
godot/game/session.gd
godot/features/player/player.tscn    # CharacterBody2D, collision, visual, Camera2D
godot/features/player/player.gd
godot/features/cherry/cherry.tscn    # stable ID, overlap signal, visual
godot/features/hazard/hazard.tscn    # fatal contact signal
godot/features/finish/finish.tscn    # completion request
godot/ui/main_menu.tscn
godot/ui/hud.tscn
godot/ui/pause_menu.tscn
godot/ui/results.tscn
godot/levels/course_01.tscn          # authored spawn, geometry, IDs, boundary
godot/tests/                        # planned deterministic behavior fixtures
```

Keep private art beside its owner; share only genuinely reused assets. The sibling `jumping-man-godot/` collection's recovered art and Unity scripts remain untouched; only reviewed selected assets would enter the new project. Do not create a project at the Walker toolkit root or import all twelve recovered collections into the pilot.

**Collision categories:** World, Player, Pickup, Hazard, Goal, MovingPlatform. Explicitly document each bit/mask in project configuration; the player collides with solid world/platforms, while triggers detect only Player. Decorative sprites have no collision. Use groups/types and explicit references, not checks against a node's display name.

**Signals:** player death request, cherry collected request with stable ID, finish reached request, and session state/counter changes. The session controller commits changes after applying precedence; presentation observes the committed result.

### Input, camera, and presentation

| Action | Initial keyboard binding | Context |
|---|---|---|
| move_left / move_right | A/D and Left/Right arrows | Playing |
| jump | Space | Playing; fresh press |
| pause | P or Escape | Playing/Paused; Escape can also dismiss UI |
| UI navigation / activate | Arrows/Tab, Enter or Space | Menus; must not leak into gameplay |

Use Godot input actions so controls and UI prompts can reflect remapping. [Official input documentation](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html)

Logical viewport: **960 × 540**; normal review window: 1280 × 720. Keep the aspect ratio. Integer canvas scaling is the usual advice for pixel assets, but the property that matters is that one source pixel lands on one screen pixel: the cast is drawn at 0.75 world size and the canvas is magnified 4/3, and those multiply to exactly 1. Changing one without the other is what makes the art look blocky — it was proposed at 640 × 360, which magnified 2× and so showed three-quarter-size art at 1.5×. Validate another window size and the Web canvas. HUD text starts at 14 logical pixels minimum; the HUD is laid out in its own 640 × 360 space and its layer is scaled to fill the viewport, so that baseline is unchanged. A tuning baseline, not a universal accessibility certification.

The camera follows with level bounds and enough look-ahead to show required landings. No shake in the MVP. Reposition directly on reset so the view does not pan across the entire course before control returns. Camera motion must not introduce a mandatory blind jump.

Color reinforces shape and labels; it is never the only hazard cue. Muted play remains fully understandable. Music is optional and absent from the greybox. If effects are added, provide separate cues for jump, pickup, death, and completion without masking control feedback.

### Asset maturity and provenance

| Stage | Meaning | Acceptance |
|---|---|---|
| L0 Greybox | Original shapes, no paid generation | Collision/readability tests can run |
| L1 Proxy | Temporary art with documented source | No unclear import scale or substituted collision |
| L2 Alpha | Selected visual direction | Required poses/cues exist; no logic tied to animation completion |
| L3 Beta | Consistent, rights-cleared set | Camera/HUD/muted-route checks rerun |
| L4 Ship-ready | Final selected assets | Attribution recorded, no broken imports, export reviewed, human presentation approval |

For every selected asset, record its source, author/owner if known, license evidence, modifications, destination, and review status. Unknown rights remain unknown. The toolkit's upstream MIT license is not a blanket provenance record for recovered third-party art.

Godot's adjacent asset `.import` files hold import configuration and should be versioned; `.godot/` is generated cache. Keep source assets and UID sidecars needed to reproduce the game. [Official import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/import_process.html)

Ignore credentials, caches, recordings, and export packages. Do not blanket-ignore all playable source assets. Large-source handling needs an explicit reproducible retrieval plan with checksums; “it is somewhere on Drive” is insufficient.

### Performance and export criteria

Proposed targets, all unmeasured: 60-Hz physics; 60-fps presentation on the named reference machine at 1280 × 720; no sustained frame rate below 55 fps during a 60-second representative route; controllable warm respawn within one second; warm local start within five seconds. Record OS, CPU/GPU, engine, browser, display/vsync conditions, measurement method, and observed results. Minimum hardware and network-load targets are not yet established.

Use the Compatibility renderer for the proposed Web target. Godot's Web documentation currently specifies WebGL 2.0/Compatibility, notes that Godot 4 C# cannot export to Web, and describes single-threaded export. This motivates, but does not itself approve, the proposed GDScript profile. [Official Web export documentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)

Test the generated Web package through a local server, not merely by double-clicking HTML. Verify input focus, audio after user interaction, restart, resize, and the actual zero/all-cherry routes in the selected browsers. A packaged directory is not evidence that it ran. Public deployment and native distribution/signing are separate decisions.

### Walker stage handoff contract

| Stage | Required artifact/evidence | Exit condition |
|---|---|---|
| Game brief | Brief, GDD revision, open questions, human gate records | Scope/engine choice reviewed for the authorized slice |
| Build | Runnable isolated project, implementation-to-feature map, engine identity, logs | Slice imports and runs; no “verified” feature without tests |
| Playtest | Cases from Appendix B; anonymous human observations | Actual results captured, including failures |
| Inspect | Defect report linked to requirement/build IDs | One next change justified; no silent requirement relaxation |
| Revise | Changed files, design reason, affected tests, retained prior working version | Relevant tests rerun; changed design approvals reviewed |
| Export | Local package, file hashes, clean-start evidence | Agreed target played successfully; publication still unauthorized |

No Walker build/playtest/export executable is installed by this GDD. The reusable Zelda material is an authoring prompt and command specification. A future adapter must implement these contracts rather than printing success messages around missing operations.

## 15. Risk register

Likelihood and impact are qualitative planning judgments, not measured probabilities. Owners below are proposed responsibilities.

| ID / category | Risk | Likelihood / impact | Trigger | Mitigation / contingency | Proposed owner |
|---|---|---|---|---|---|
| RISK-01 / Design | Movement feels unfair despite correct physics | Medium / High | Repeated unexplained misses in human sessions | Greybox early; revise acceleration/gaps before art | Bear + AI implementer |
| RISK-02 / External | Recovered assets lack adequate provenance | High / High for redistribution | Selected asset has no license evidence | Original placeholders; replace or obtain clearance before release | Bear |
| RISK-03 / Technical | C# guide / GDScript target conflict or unavailable export toolchain | High / High until resolved | Agent follows wrong profile; export templates missing | Pin agreed profile and engine before build; do not silently switch target | AI implementer, Bear approves |
| RISK-04 / Technical | Reset leaks state or duplicates collection/completion | Medium / High | Counters differ after repeated retries | Single state owner, stable IDs, event precedence tests | AI implementer |
| RISK-05 / Scope | Art catalogue drives unplanned mechanics | High / Medium | Fan/wall-jump assets become a feature request mid-build | Enforce feature IDs and explicit scope review | Bear |
| RISK-06 / Production | Automatic loop retries failures without useful progress | Medium / High | Repeated identical error or missing dependency | Bounded retries, stop with evidence, preserve working build | Walker tooling owner |
| RISK-07 / Production | Disk pressure during import/capture | Medium / Medium | Insufficient free space for planned outputs | Import only pilot assets, estimate space, no unrequested cleanup | Walker tooling owner |
| RISK-08 / Accessibility | Input or visual design excludes intended players | Medium / High | Controls unreadable, unremappable, or misleading when muted | Keyboard/focus/muted checks, human testing, revisit audience claims | Bear + AI implementer |

**Top risk 1 — feel:** a clean import and correct jump formula can still produce a bad game. Do not finance polish around an untested controller. The first human session should happen with shapes.

**Top risk 2 — provenance:** an attractive sprite sheet is not evidence of permission. The pilot can be fully playable with original placeholders, so rights uncertainty should not be disguised as a technical blocker or ignored at release.

**Top risk 3 — toolchain mismatch:** the existing source toolkit instructs agents to use C#. This GDD proposes another profile for a concrete export reason. Resolve and record the choice before implementation; a prompt should not silently choose whichever engine guide is convenient.

## 16. Open questions and human decisions

No calendar deadlines have been invented. “Before” milestones are decision deadlines; none is represented as an overdue human commitment.

| ID | Question and stakes | Draft default / alternatives | Owner / deadline / status |
|---|---|---|---|
| Q-01 | Is this a new small platformer or a faithful reconstruction? | New design informed by recovered mechanics; faithful reconstruction would require more source | Bear / before vision approval / OPEN |
| Q-02 | Approve GDScript + Compatibility + local Web delivery? | Proposed; C# desktop-only is a different approved target | Bear / before build / OPEN |
| Q-03 | Accept one level, optional cherries, no checkpoints? | Proposed compact MVP; shrink further or revise scope explicitly | Bear / before scope approval / OPEN |
| Q-04 | What is the desired feel? | Readable and forgiving rather than expert-only precision | Bear / first greybox review / OPEN |
| Q-05 | Which art may be redistributed? | Original placeholders until records exist | Bear / before selecting release assets / OPEN |
| Q-06 | Which machine/browsers define acceptance? | Mac desktop plus named installed browser versions; minimum hardware unknown | Bear + AI implementer / before performance/export tests / OPEN |
| Q-07 | Does full-level retry stay enjoyable? | Start without checkpoints; inspect actual friction | Bear / after first human session / OPEN |
| Q-08 | What is the first example project's name? | walker-jumpman; every new game project uses the walker- prefix | Bear / specified 2026-09-10 / DECIDED |

**Largest immediate choices:** approve the proposed language/export profile and the one-level scope. The rest can be refined from the greybox without pretending a polished design is already proven.

Human gate ledger: Vision pending; Systems pending; World pending; Scope pending. Educational audit inactive. Production task document drafted under Bear's explicit request to complete all design work; implementation remains unstarted. No approval is inferred from this document's existence.

## Appendix A. Recovered source evidence and adaptation decisions

All eleven recovered C# scripts were inspected. They import Unity APIs; there is no recovered `project.godot` or scene wiring establishing a runnable Godot version.

| Source | Observed code | Adaptation / uncertainty |
|---|---|---|
| [PlayerMovement.cs](../jumping-man-godot/unity-scripts/scripts/PlayerMovement.cs) | Horizontal input, Rigidbody2D velocity, grounded BoxCast jump, animation/facing states; default speed/jump 7 | Preserve intent, not units; Godot tuning, acceleration, coyote and buffer are new proposals |
| [PlayerLife.cs](../jumping-man-godot/unity-scripts/scripts/PlayerLife.cs) | Trap collision disables body and triggers death; restart method reloads scene | Invocation/wiring of restart not recovered; use explicit bounded reset |
| [item_collector.cs](../jumping-man-godot/unity-scripts/scripts/item_collector.cs) | Cherry trigger destroys object, increments count, updates UI/global score | Per-attempt unique-ID scoring and reset semantics are new, explicit requirements |
| [AllControl.cs](../jumping-man-godot/unity-scripts/scripts/AllControl.cs) | Singleton integer score | Do not infer working multi-level persistence or correct resets |
| [Finish.cs](../jumping-man-godot/unity-scripts/scripts/Finish.cs) | Player-name trigger, repeat guard, two-second delayed next build index | Explicit completion state and scene reference replace index arithmetic |
| [StartMenu.cs](../jumping-man-godot/unity-scripts/scripts/StartMenu.cs) | Starts scene at current build index plus one | Use an explicit level reference |
| [EndMenu.cs](../jumping-man-godot/unity-scripts/scripts/EndMenu.cs) | Loads current build index minus three | Does not prove the number or order of original gameplay levels |
| [Camara.cs](../jumping-man-godot/unity-scripts/scripts/Camara.cs) | Direct player X/Y follow | Bounds/look-ahead/reset behavior require new design and tests |
| [WaypointFollower.cs](../jumping-man-godot/unity-scripts/scripts/WaypointFollower.cs) | Cycles waypoint array with MoveTowards and distance threshold | Follow-up; validate endpoint data and reset phase |
| [StickyPlatform.cs](../jumping-man-godot/unity-scripts/scripts/StickyPlatform.cs) | Parents/unparents object named Player on trigger enter/exit | Godot body/platform behavior is not a literal parenting port |
| [Rotate.cs](../jumping-man-godot/unity-scripts/scripts/Rotate.cs) | Constant transform rotation | No mandatory rotating obstacle is inferred |

The 115 recovered art files include terrain, character animation sheets, fruit, traps, backgrounds, and a font. Their presence establishes available files, not approved mechanics, rights, original scene composition, or tested animation slicing. The recovered collection contains no audio files; any runtime effects are new work.

## Appendix B. Acceptance and playtest matrix

**All cases below are NOT RUN.** They specify future checks. Automated/assisted labels describe the intended method, not existing test software. Each recorded result must include revision, build identity, engine version, actual observation, timestamp, and evidence location.

| Case | Setup and action | Expected result / measurement | Method / requirement |
|---|---|---|---|
| CASE-001 | Fresh project checkout/copy without local import cache; import and start main scene | No missing resources or script errors; all start/menu references resolve | Automated + visual; FEAT-08 |
| CASE-002 | Flat-floor fixture; hold right for 1 s after start, release, then reverse; repeat at different render frame caps | Speed cap 160 px/s, time to speed about 0.125 s; release/reversal match configured rates within one physics tick; same fixture endpoints within 1 px across render caps on pinned engine | Automated; MECH-01 |
| CASE-003 | Hold both directions; run into a wall; reverse at a ledge | Neutral intent decelerates; no wall penetration; no input-priority flicker; camera does not hide required destination | Automated + visual; MECH-01 |
| CASE-004 | Jump from flat ground with no ceiling, then repeat with low ceiling | Apex/flight measured against configured physics with documented tolerance; no second jump from ceiling contact | Automated; MECH-02 |
| CASE-005 | Step off floor, press at ages 5, 6, and 7 ticks; buffer before landing at corresponding ages | 5 and 6 accepted; 7 expired; each request consumed once | Automated; MECH-02 |
| CASE-006 | Hold jump through landing, repress midair, then die with buffered jump | No auto-bounce or double jump; death clears buffer; fresh press required after reset | Automated; MECH-02, MECH-04 |
| CASE-007 | Repeated contact with one cherry, two distinct contacts in same tick, death and retry | Awards exactly 1 then 2 as appropriate; retry restores 20 available cherries and zero attempt score | Automated; MECH-03 |
| CASE-008 | Traverse direct route with zero cherries; separately traverse all-cherry route | Both finish; total never exceeds 20; every cherry reachable by allowed movement | Scripted route + human; MECH-03, FEAT-06 |
| CASE-009 | Trigger a hazard twice, two hazards together, and fall out of bounds | Exactly one death per attempt; clear cause; no extra transition or score leak | Automated + visual; MECH-04 |
| CASE-010 | Perform 20 automatic deaths/retries, with animation omitted in a fixture | Each respawn restores coherent state within 1 s; count increases exactly once each; no accumulated stale nodes/events | Automated + timing; MECH-04 |
| CASE-011 | Inject pickup/death/finish events in varied orders within one tick | Fatal event wins and suppresses awards/finish; otherwise finish includes valid same-tick cherries; identical final state regardless of callback ordering | Automated; §7 |
| CASE-012 | Reach finish repeatedly with 0, some, then all cherries | One completion, correct result, no next-level assumption or minimum-score gate | Automated + visual; MECH-06 |
| CASE-013 | Replay twice, return to menu, start again; double-activate Replay | One new session; all attempt/session counters correctly reset; no duplicate level | Automated + UI; MECH-06 |
| CASE-014 | Pause midair; lose focus with movement held; return focus; resume | Gameplay and timers freeze; menus work; focus return does not auto-resume; no unintended gameplay jump from menu activation | Assisted + automated; MECH-07 |
| CASE-015 | Keyboard-only start/settings/pause/results; remap jump, conflict a binding, restore defaults; simulate bad preferences file | Reachable focus order, updated prompts, conflict handled, defaults recover; no mouse needed | Assisted; MECH-07, PX-06 |
| CASE-016 | Play muted at 1280×720 and another window/canvas size | Hazards, collection, failure and completion remain legible; no clipped essential UI or color-only instruction | Human visual; PX-06 |
| CASE-017 | Follow-up platform fixture: ride, reverse, leave, jump, reset; malformed endpoints | No parenting jitter/teleport/extra boost; bad path safely diagnosed; deterministic reset phase | Deferred; MECH-05, FEAT-09 |
| CASE-018 | 60-second representative run on recorded reference machine | Report frame timing; target 60 fps, no sustained <55 fps for >1 s; record stalls and warm start time | Instrumented + visual; §14 |
| CASE-019 | Export, serve locally, cold-open selected browsers; play zero/all-cherry routes, mute, resize, retry | Real package runs; controls/audio activation/reset work; no blocking runtime/browser-console errors; actual exported files hashed | Assisted; FEAT-08 |
| CASE-020 | Five voluntary formative sessions: aim for 3 newcomers and 2 experienced players; no coaching during first attempt | Record cause-of-death explanation, control confusion, retries, and completion time; investigate any recurring unfairness | Human; PX-01, PX-02, PX-04 |
| CASE-021 | Observe optional-route choice and muted keyboard play; ask what counts as winning | Players understand cherries are optional and can describe the finish; log barriers rather than claiming universal accessibility | Human; PX-03, PX-05, PX-06 |
| CASE-022 | Select assets for release; compare manifest, source/license records, export contents | Each shipped asset has provenance and reviewed terms; no recovered asset silently enters package; no secrets/logged personal data shipped | Document + package review; §14 |

For CASE-004, the continuous estimates are about 53.3 px rise and 0.667 s flight. Establish the discrete solver baseline on the pinned engine; initially investigate differences greater than 5 px or two physics ticks. Do not change tolerances just to hide a defect.

Five sessions are formative, not a statistically representative study. A proposed review trigger is fewer than four participants being able to explain their failures or identify the optional route. Record actual counts and quotations with consent; do not convert a small sample into a claim that the game is universally fair or fun.

## Appendix C. Traceability and first iteration

| Feature | Proposed Godot owner | Evidence needed before “verified” |
|---|---|---|
| FEAT-01–02 | Player scene/controller | CASE-002–006, human CASE-020 |
| FEAT-03 | Session + hazard + level boundary | CASE-009–011 |
| FEAT-04 | Session + finish + menu/results UI | CASE-012–013 |
| FEAT-05 | Cherry scene + session counter | CASE-007–008, CASE-021 |
| FEAT-06 | Course, Camera2D, HUD | CASE-003, CASE-008, CASE-016, CASE-020–021 |
| FEAT-07 | Pause/settings/input ownership | CASE-014–016 |
| FEAT-08 | Project/import/export configuration | CASE-001, CASE-018–019, CASE-022 |
| FEAT-09 | Optional platform scene | CASE-017 only after authorization |
| FEAT-10–12 | Not assigned | Require approved specifications and new tests before implementation |

**First iteration hypothesis:** a small, readable controller with a quick retry is sufficient to make a single obstacle worth trying again. Build only the first approved slice, record one success and one failure/retry, and inspect human reactions. A clip is evidence of those runs, not evidence for every acceptance case.

If movement changes, reopen the jump-envelope and level-spacing checks. If scope changes, update this document and approval state before expanding the build. If a test fails, preserve the failing record rather than replacing it with a narrative claim.

## Appendix D. Revision history and next handoff

| Revision | Date | Author | Design reason and changes |
|---|---|---|---|
| 0.1.0 | 2026-09-10 | AI-assisted draft for Bear | Named the first example walker-jumpman per Bear; converted recovered-script observations into a bounded one-level Godot proposal; made new tuning/reset assumptions explicit; added scope, traceability, and test requirements |
| 0.2.0 | 2026-09-10 | AI-assisted design package for Bear | Added candidate level coordinates/map, asset requirements, production tasks and a playtest protocol under the request to finish all design work; no human approval or runtime result inferred |

No source scripts or art were modified. No gameplay test, export, asset generation, public release, human approval, or production ticket execution occurred.

**Next handoff:** Bear reviews the brief and consequential assumptions. After build authorization, create the isolated Godot greybox, record the actual toolchain, and test the first slice. The [production plan](PRODUCTION-PLAN.md) is ready to guide that authorized build.
