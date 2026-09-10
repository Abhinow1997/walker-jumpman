# walker-jumpman — Asset and presentation plan

Design revision: 0.2.0 · **Specification only; no runtime art/audio created or selected.**

The first playable build uses original geometric placeholders. The [level overview](design/level-overview.svg) is an original design diagram, not final game artwork or a screenshot. No paid generation is authorized.

## Runtime asset requirements

| ID | Required role | L0 proposal | Later acceptance |
|---|---|---|---|
| ART-001 | Player | Simple upright body with facing marker; fixed collision outline | Idle/run/rise/fall/death are legible; poses do not resize collision |
| ART-002 | Ground/platform | Solid dark surface with a distinct top edge | Walkable bounds match art; background does not imitate it |
| ART-003 | Cherry | Round fruit shape with stem, distinct from hazard | Recognizable without color alone; available/consumed states clear |
| ART-004 | Stationary hazard | Repeating triangular silhouette | Dangerous area visible before approach; no invisible oversized collider |
| ART-005 | Finish | Flag/goal silhouette with “Finish” label | Not mistaken for a cherry or required checkpoint |
| ART-006 | Start and direction | Spawn marker plus brief key-action prompts | Prompts update after remapping; no text wall before play |
| ART-007 | HUD/results/menu | Readable text, focus outlines, plain buttons | Keyboard-only operation, no clipping, correct counters |
| ART-008 | Feedback | Minimal pickup/death/success flashes or shape changes | Muted play still communicates outcome; no flashing dependency |
| ART-009 | Background | Flat neutral field | No collision; high separation from play surfaces |
| SND-001 | Jump/pickup/death/finish effects | Optional; omit in first greybox | Original or rights-cleared files; mute works; never govern state |
| SND-002 | Music | Absent | Optional future approval; never required for gameplay |
| FONT-001 | UI typeface | Built-in Godot default for greybox | Record font source/license if replacing it; legibility review |

## Recovered-source policy

The sibling [recovery collection](../jumping-man-godot/) contains art, a font, and Unity scripts, but no audio. Inspecting these files does not approve their redistribution. The upstream toolkit license is not a substitute for an individual asset's provenance.

Do not infer that sprite names authorize double jumps, wall jumps, fans, checkpoints, or other mechanics. No recovered asset is selected for runtime use by this plan.

For any proposed reuse, record: asset ID; exact source path; original author if known; source URL/acquisition context; license and evidence; proposed use; modifications; destination; reviewer; approval state; file hash. Keep unknowns explicit. Human permission or a replacement asset may be required before public release.

## Pipeline and constraints

L0 original greybox → L1 documented proxies → L2 selected visual language → L3 consistent rights-cleared set → L4 reviewed release assets. A phase label is not automatically granted when a file exists.

Keep a scene's private assets beside that feature. Do not bulk-copy the recovered library. Preserve source art, import configuration and identity metadata; exclude Godot cache, secrets, captures and packages from source commits. Prefer small necessary assets; large media requires an explicit retrieval/size policy.

The level map uses labeled shapes because it communicates geometry, not an approved aesthetic. Visual style remains a human choice. Do not copy Brutalist's video constraints such as 4K or a presenter persona into game runtime requirements.

## Approval before generation

There is no asset-spend requirement for the first slice. If later generated assets are desired, present the particular assets, provider, estimated cost, and intended use for approval before making calls. Log actual provenance and cost. A request to finish design work is not that spending approval.
