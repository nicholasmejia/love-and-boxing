# Sweat Particle FX — Design

**Date:** 2026-05-24
**Status:** Design approved; awaiting implementation plan

## Goal

When the player lands an attack on the opponent, spawn a brief, kinetic
spray of "sweat" droplets at the impact zone, flying off in the direction
the punch was traveling.

Distinct from the existing single-drop `ReactionEmoteNeutral` (which
fades in, slides down, fades out over ~1s for riddle reactions). The new
FX must read as plural, fast, and physical — not contemplative.

## Constraints

- **Web export target (itch.io).** Use `CPUParticles2D`. Avoids
  `GPUParticles2D`'s historical web-export quirks; particle count is too
  low for GPU advantages to matter.
- **No new audio.** Existing `combo_success_*` and `opponent_punch_body`
  SFX already fire on the same frame and carry the impact beat.
- **Must not visually compete with WASD prompt animations** that also
  fire on the impact frame.

## Architecture

### Approach: 4 pre-configured emitters + thin router

A new scene `scenes/fx/sweat_fx.tscn` (root `Node2D` named `SweatFX`,
script `scripts/fx/sweat_fx.gd`) holds four `CPUParticles2D` children —
one per attack direction. Each is pre-wired with its own anchor offset
and launch vector. A `emit_for(direction: int)` API on the parent calls
`restart()` on the matching child.

Mounted as a child of `Opponent` so the anchor offsets are local to the
opponent's transform.

**Why 4 emitters, not 1 reconfigured:**
The 3-hit finisher fires `_on_attack_step_landed` up to three times per
combo, with `_PUNCH_FLASH_SECONDS` (~0.18s) between landings. Particle
lifetime is ~0.6s, so consecutive bursts overlap by design. A single
shared emitter would have its in-flight particles wiped by the next
`restart()`. Four independent emitters let overlapping bursts play in
parallel without interference.

### Scene tree

```
Opponent (existing Node2D, world pos 960,400)
├── Body (existing Sprite2D)
├── ReactionEmoteNeutral (existing)
├── ReactionEmoteWrong (existing)
└── SweatFX (new — instance of scenes/fx/sweat_fx.tscn)
    ├── Head  (CPUParticles2D)
    ├── Left  (CPUParticles2D)
    ├── Body  (CPUParticles2D)
    └── Right (CPUParticles2D)
```

### Direction routing

`SweatFX._emitters: Dictionary` maps `SimonSequence.Direction` →
`CPUParticles2D` child. `emit_for(direction)`:

1. Looks up the matching emitter.
2. Calls `emitter.restart()` — instantaneous burst due to
   `one_shot = true` + `explosiveness = 1.0`.

No per-call reconfiguration; all per-direction tuning lives on the
emitter nodes themselves.

## Tuning constants

All defined at the top of `scripts/fx/sweat_fx.gd` so playtest iteration
is a single-file change. Values below are starting points; final numbers
land during playtest.

### Per-direction anchor offsets (local to Opponent)

Pinned to the opponent Body sprite's visual head/torso zones. Opponent
Body is at local `(0, 820)` with scale `0.85`.

**These Y values are placeholder guesses pending visual verification in
the editor** — Body's center sits below the viewport (world `(960, 1220)`
on a 1920x1080 viewport), so the visible character must extend upward
from its center. The actual head and torso Y-positions depend on the
texture's pixel layout; the implementer should open the scene, drag the
emitter nodes onto the visible head and torso, and snapshot the
resulting offsets back into these constants.

```gdscript
const IMPACT_OFFSETS := {
    SimonSequence.Direction.HEAD:  Vector2(  0, 690),  # head front  — VERIFY
    SimonSequence.Direction.LEFT:  Vector2(-90, 690),  # head, opp.'s right cheek  — VERIFY
    SimonSequence.Direction.BODY:  Vector2(  0, 820),  # torso center  — VERIFY
    SimonSequence.Direction.RIGHT: Vector2( 90, 690),  # head, opp.'s left cheek  — VERIFY
}
```

### Per-direction launch vectors (unit-ish)

Sign convention matches `WasdPrompt.toss_horizontal_for()` so the prompt
toss and sweat spray fly the same direction the punch was traveling.
Y is negative (upward in Godot 2D) for all four.

```gdscript
const LAUNCH_VECTORS := {
    SimonSequence.Direction.HEAD:  Vector2(-0.5, -1.0),  # jab → up-left
    SimonSequence.Direction.LEFT:  Vector2( 1.0, -0.6),  # hook → right + up
    SimonSequence.Direction.BODY:  Vector2( 0.5, -1.0),  # jab → up-right
    SimonSequence.Direction.RIGHT: Vector2(-1.0, -0.6),  # hook → left + up
}
```

Each `CPUParticles2D.direction` is set to the matching `LAUNCH_VECTORS`
entry. Godot interprets `direction` as the central axis of the emission
cone; `spread` rotates around it.

### Shared CPUParticles2D config (all 4 emitters identical)

| Property | Value | Notes |
|---|---|---|
| `amount` | `12` | Inside the "medium burst" range 10–15 |
| `one_shot` | `true` | Single burst per `restart()` |
| `explosiveness` | `1.0` | All particles emit on frame 0 |
| `emitting` | `false` | Set in the editor; `restart()` triggers each burst |
| `lifetime` | `0.6` | Long enough to see the full gravity arc |
| `gravity` | `Vector2(0, 980)` | ~Earth-ish fall rate at this px scale |
| `initial_velocity_min` | `180` | px/s |
| `initial_velocity_max` | `320` | px/s |
| `spread` | `18` | degrees — narrow cone around `direction` |
| `scale_amount_min` | `2.0` | default-square ×2 |
| `scale_amount_max` | `4.0` | default-square ×4 |
| `color` | `Color(0.72, 0.80, 0.86)` | Light-blue-grey base |
| `color_initial_ramp` | gradient | Near-grey `(0.78,0.80,0.82)` → cool blue-grey `(0.65,0.78,0.92)`; each particle samples a random point for per-droplet saturation variance |
| `color_ramp` | alpha fade | `1.0 → 0.0` over lifetime |

No `texture` — default white-square render, recolored via `color` +
ramps per question 3 / option C.

## Integration

### Opponent API

`scripts/actors/opponent.gd` gains:

```gdscript
@onready var _sweat_fx: SweatFX = $SweatFX

func play_sweat(direction: int) -> void:
    _sweat_fx.emit_for(direction)
```

### Call site

`scripts/gameplay.gd` `_on_attack_step_landed(index)` — directly after
the existing `_hit_opponent_for(direction)` call at line 472:

```gdscript
_hit_opponent_for(direction)
_opponent.play_sweat(direction)
_gloves.set_state(PlayerGloves.State.PUNCH, direction)
```

Same frame as the impact SFX (`combo_success_*` + `opponent_punch_body`)
and the opponent's `HIT_*` pose — visual + audio + FX all land together.

## Files touched

**New:**
- `scripts/fx/sweat_fx.gd` — class with constants + `emit_for()` API
- `scenes/fx/sweat_fx.tscn` — scene with 4 pre-configured `CPUParticles2D` children

**Modified:**
- `scripts/actors/opponent.gd` — `@onready var _sweat_fx` + `play_sweat()` method
- `scenes/actors/opponent.tscn` — add `SweatFX` instance as child of `Opponent`
- `scripts/gameplay.gd` — single line added in `_on_attack_step_landed`

## Testing

No unit tests. Pure visual FX, motion-tuned by playtest. Verification is
running the build, landing combos at all 4 directions and at finisher
density, and confirming:

1. Each direction's burst originates from the correct zone on the opponent.
2. Drops fly the same direction as the prompt's toss-out animation.
3. Gravity arc reads as physical, not floaty.
4. Per-particle saturation variance is visible (drops aren't a uniform monochrome blob).
5. Overlapping finisher bursts don't visually erase each other.
6. No frame stutter on web export.

## Out of scope

- Custom droplet sprite (deferred; default squares with color treatment ship first).
- Sweat on the player (this is opponent-only impact feedback).
- Sweat on opponent SWING animations (this fires on the player's landed attacks only).
- Tuning automation / debug overlay (constants in source file are sufficient).
