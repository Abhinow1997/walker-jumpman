# First Steps — playable slice

Built September 10, 2026 under Bear's request: **“Build a simple level for walker-jumpman.”** This is the small control/retry prototype, not the full three-zone, twenty-cherry GDD or a public game release.

## What is implemented

- A 960 × 360 level, two small steps, 64- and 48-pixel gaps, one three-spike hazard, and a finish flag.
- Typed GDScript player; the proposed speed, acceleration, jump, gravity, and six-tick forgiveness settings.
- Start, movement, fixed-height jumping, automatic retry, manual restart, pause/focus safety, finish/results, and replay.
- A bounds-clamped camera with forward view, controls/progress/timer/retry HUD, and original geometric artwork. No recovered artwork or paid services.
- A local double-click launcher, editable source, machine test fixtures, and rendered game screenshots.

Cherries, the larger course, audio, remapping/settings persistence, moving platforms, and distributable exports are not implemented in this slice. No human enjoyment/fairness judgment has been filled in by an agent. The four full-design gate signatures remain pending; this request authorizes the simple build, not every proposed feature.

## Checks and revisions

Godot **4.7.2.stable.official.ed1daf0bf**, Compatibility/OpenGL, 60-Hz physics; macOS 26.5.1, Apple M4 Pro. Regular engine, no .NET dependency. Default view 1280 × 720, logical resolution 640 × 360.

The first 25-check run found four failures, retained in [the original report](evidence/mechanics-1789078423.29998.json): stale Area2D contacts after teleporting to spawn created a second death, and the first route lacked a safe landing between a hazard jump and a gap. Fixes discard only the two pre-reset contact snapshots and separate those landing decisions. The jump tuning and acceptance tolerances were not weakened.

The next [25-check run](evidence/mechanics-1789078494.18347.json) passed. It covers speed/stop/opposing inputs/wall contact, jump height, no double jump or held-key bouncing, six/seven-tick coyote and buffer boundaries, a low ceiling, pause/focus, actual spike contact, fall boundary, event precedence, replay, and twenty consecutive retries. Coyote/buffer boundary cases explicitly seed controller timing state; they are unit fixtures, not a claim to cover every naturally occurring landing sequence.

Observed jump rise: **56.07 logical pixels**. Largest automatic retry interval: **34 physics ticks**, approximately 0.567 seconds. The deterministic input route reached the real finish with **zero deaths**, five jumps, in **325 ticks** (about 5.42 seconds). This fast known route is not a predicted new-player completion time.

Nine additional passing keyboard checks inject key events through Godot's Input system: start, movement, jump, pause, resume, retry, replay, menu, and restart from menu. Real rendered-viewport captures cover menu, a spike failure, a jump over the gap, and completion. The normal main-scene launch also ran without script errors. [The build manifest](evidence/build-manifest.json) records the latest 34-check evidence inventory and exact source hashes.

A source-only copy at `/tmp/walker-jumpman-clean.yrT1x4`, excluding `.godot/`, passed a fresh editor import and normal main-scene launch (both exit 0). The canonical game was then launched for Bear. All 17 recorded source hashes still match; the protected original project's configuration hash is unchanged.

## Repeat the local checks

From this package, run Godot with `--headless --path godot --script res://tests/test_game.gd`, then `res://tests/test_keyboard.gd`. The visual capture uses `--path godot --script res://tests/capture_game.gd` without headless mode and saves the engine's rendered viewport, not a desktop screenshot. After passing checks, `node scripts/record-build.cjs` records the source snapshot. [The launcher](walker-jumpman.command) runs the normal main scene, not a test driver.

## Human review and boundaries

Double-click [walker-jumpman.command](walker-jumpman.command), press Enter, and play. Check whether each jump feels understandable, whether you can see the next landing, and whether the quick retry feels useful. AI checks mechanics; you judge the game.

The original `/Users/bear/walker-jumpman` and the recovered `jumping-man-godot` assets were not modified. This build lives only in this package's `godot/` child. Export templates are absent; no export download, Web package, repository push, or game publication occurred. The separate setup film can describe an empty project historically without claiming this new level existed when it was recorded.
