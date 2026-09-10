# walker-jumpman — Game brief

Version: 0.2.0 · September 10, 2026 · **Draft for human review**

**Build update:** the subsequently authorized [First Steps prototype](README.md) is now playable. It implements the small movement/jump/hazard/retry/finish slice; the larger design below remains proposed. See [actual results](BUILD-REPORT.md).

The project name is **walker-jumpman**, following Bear's requirement that every new game project starts with `walker-`. This is Walker's first small Godot platformer, not a claim to reproduce another commercial game. The detailed specification is [GDD.md](GDD.md); approval and implementation state are in [DESIGN-STATUS.json](DESIGN-STATUS.json).

## The game in one paragraph

You are a nimble little runner crossing a compact obstacle course. Read the landing, commit to a jump, and decide whether an optional cherry is worth a harder route. A mistake sends you back quickly, without a lives counter or a lecture. Reaching the finish wins; collecting every cherry is a self-chosen mastery challenge. The promise is: **“I can see why that failed, and I want one more try.”**

## Player, experience, and scope

- Audience hypothesis: players comfortable with a keyboard who want a short, readable platforming challenge. Test with both newcomers and experienced platformer players.
- One single-player, three-zone level; no combat, inventory, online services, procedural generation, or required narrative exposition.
- Left/right movement and one fixed-height jump; small input-forgiveness windows; no double jump or wall jump.
- Twenty optional cherries, stationary hazards, unlimited retries, a visible finish, and replay.
- First-play session target: roughly 2–4 minutes, to be validated rather than padded. Completion must be possible with zero cherries.
- Moving platforms are documented as a follow-up; the initial route does not depend on them.
- No educational track is active. Walker may teach its creator, but this game is not being represented as a validated learning intervention.

## The player’s decisions

**Micro:** where to land, when to jump, whether to commit.
**Level:** take the direct route or risk a cherry detour.
**Replay:** finish more cleanly or collect more cherries.

The course progresses from safe movement practice, to optional risk, to combining familiar jumps and hazards. It introduces no unavoidable new rule immediately before the finish.

## Godot target — proposed, not yet approved

Godot 4 with typed GDScript, a 2D Compatibility-renderer project, and a 640 × 360 logical viewport. The first review target is local desktop play on Bear's Mac; a locally served Web export is the proposed shareable target. Pin the exact installed engine and matching export templates before building.

This differs from Walker's existing C#/.NET engine guide. No engine-guide migration or runnable project has happened as part of writing this brief.

Build an isolated `godot/` child of this new `walker-jumpman/` project when implementation is authorized. Preserve the separate [recovered collection](../jumping-man-godot/) and its `art/` and `unity-scripts/` as source evidence. Use simple original placeholder shapes first, with no paid generation.

## What we actually recovered

The separate recovered `jumping-man-godot` collection contains 115 art files and 11 Unity C# scripts. Source supports horizontal movement, grounded jumping, fruit pickup, traps/death, camera following, menus, level transitions, and moving-platform behavior. Unity scenes, inspector wiring, physics settings, and original level layouts are absent. These files do not establish a playable game or prove the original balancing.

Sprite names suggesting double jumps, wall jumps, checkpoints, or fans do not make those features part of this MVP. Asset attribution and redistribution rights remain to be established.

## Walker’s first complete pass

1. **Game brief:** review this scope and the GDD's assumptions.
2. **Build:** make a greybox course with movement, one hazard, retry, and finish; then add cherries and the three-zone route.
3. **Playtest:** run the specified mechanical checks and let humans play without coaching.
4. **Inspect:** compare failures, route understanding, and controls with the GDD's test IDs.
5. **Revise:** change the smallest responsible parameter or layout; retain the prior working build and explain the change.
6. **Export:** test the local distributable from a clean start. A recording demonstrates a run; it does not replace testing. Uploading is a separate approval.

## Human and AI contributions

The AI may draft the design, propose scene structure, implement authorized work, run checks, and summarize observed failures. Bear owns scope, visual direction, release decisions, and approval. Human players provide evidence about fairness, readability, and enjoyment.

All design numbers are starting hypotheses. All approvals are pending. No Godot build, gameplay test, export, paid asset generation, or publication is claimed.
