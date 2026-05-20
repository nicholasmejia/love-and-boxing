# Actor Animations — Design

**Date:** 2026-05-19
**Status:** Final spec. Ready for plan + implementation.
**Branch (to be cut):** `feature/actor-animations` off `main` (after pulling — the MVP branch was merged in, so `feature/love-and-boxing-mvp` is no longer the right base).

## Goal

Add visual "life" to the existing sprite-swap actors:

- **Player gloves (Gorgeous)** — continuous sway when idle; directional block poses (both gloves participate); per-direction punch throw with shrink + rotation.
- **Opponent** — boxer-footwork idle bob; directional shift + grow-then-shrink during attacks; directional shift + shrink-then-grow during hits; multi-phase knockdown fall and recover; vertical excitement bounce while guard-dropped.
- **Per-opponent style profiles** — Tofu (wild), Minty (refined), Sebastian (efficient). Tofu's profile tuned now; Minty/Sebastian fall back to Tofu for this branch; per-opponent tuning is a follow-up effort.

## User's full animation list (verbatim — source of truth)

```
Player
 - Gloves need to sway
 - Glove need to move in direction they are going
     - blocking: both gloves should go up
        - higher when blocking high
        - both towards middle when S
        - Left attacks: left glove a little to right and right glove further to the left
            - Right attacks: right glove a little to left and left glove further to the right
    - attacking: glove needs to shrink to give appearance of going towards opponent
            - should rotate just a little too like throwing a real punch
                - A and D attacks will attack with respective left and right gloves
        - S attacks will be with left hand and go towards center
        - W attacks will be with right hand and go towards head

Opponent
 - When in idle pose, they need to bounce in a slight arc from left to right to indicate they are moving on their feet like a real boxer
 - Depending on the direction they attack, they should shift slightly in the opposite direction of the side the attack came from while also growing then shrinking in size to indicate they are moving towards the player when attacking
    - A attacks will shift the character to the right then immediately back into place
    - D attacks will shift the character to the left then immediately back into place
    - W attack should be treated like A attacks
    - S attacks should be treated like D attacks
 - When opponent is hit, they should also shift the same way but instead of growing and shrinking, they should shrink and then grow to indicate going backwards then stepping forwards to recover from the attack
 - Knockdowns: the opponent sprite should sway left and right while slowly growing smaller to indicate losing their balance and falling backward, and then finally rotating about 40 degrees and being lowered so you can only slightly see their sprite, as if they were knocked down.  If it isn't a knockout knockdown, the opponent should pop back up into place as if they jumped off the floor to stand again
 - Guard dropped: when they drop their guard for your attack phase, until they are struck, they should bounce up and down to indicate excitement
```

**Block sub-bullets reading:** the two "Left attacks" / "Right attacks" sub-bullets sit under the *blocking* parent. They describe glove positions when blocking an A or D punch from the opponent, not when the player attacks.

## Cross-cutting note: animation timings are starting estimates

The user has flagged that gameplay beats currently feel "way too fast" and wants to see whether animation read-time improves that before doing a holistic timing pass. Therefore:

- Per-beat **durations** are starting estimates, not locked decisions. The executor treats them as defaults; the user will tune in playtest.
- A dedicated timing-tuning pass is planned as a **separate effort** after this animation phase ships.
- **Positions, scale factors, rotation angles, easing curves, and amplitudes ARE locked.** Only the time-axis values are open.

## Architecture decisions

### D1 — Glove API change (Q1 + Q4b amendment)

Animations live inside the actor classes; the dispatcher in `gameplay.gd` keeps calling semantic beats. Per-opponent variation slots in as a Resource the actor loads.

The original "preserve current call shapes" goal does NOT survive the block beat — block requires direction info (so both gloves can position per W/A/S/D), which `set_state(side, state)` doesn't carry. New glove signature:

```gdscript
PlayerGloves.set_state(state: int, direction: int = -1)
```

- `IDLE`: direction ignored; both gloves return to base + resume sway.
- `BLOCK`: direction required (`SimonSequence.Direction`); both gloves swap texture and tween to per-direction pose.
- `PUNCH`: direction required; only the punching glove (per the punch direction map) swaps texture and tweens; the other glove keeps its prior state.

`PlayerGloves.Side` enum becomes internal-only (addresses `_left` vs `_right` sprites) or is deleted if no longer referenced externally.

`Opponent.set_action(action, direction)` keeps its current shape — the opponent is a single sprite, so action+direction is already the right unit. Two new `Action` enum values are added (`HIT_BODY`, `GUARD_DOWN_EXCITED`) — both share existing textures, disambiguation is animation-only. See D5f and D5h.

Rejected: parallel `apply_block_pose(direction)` method (forces two-call-per-beat at the call site, easy to forget); parallel `play_*` methods (doubles every call site); higher-level `enact(beat, direction)` API (bigger refactor for no real win).

### D2 — Per-opponent animation profile

**New type:** `OpponentAnimationProfile` (Resource). One `.tres` per opponent under `data/opponent_animation/`. Holds the numeric knobs (amplitudes, durations, easing curves, rotation angles, sway counts) for every animation beat. Loaded by `Opponent.configure()` during scene setup.

**Wire-up:** add `animation_profile_path: String = ""` to `DifficultyConfig`. Empty/missing path falls back to Tofu's profile — same pattern as `dialogue_deck_path` at `gameplay.gd:73-76`.

**Code is singular.** Each animation beat is written ONCE in `opponent.gd` and reads its parameters from `_profile`. No per-opponent code branches.

**Player has NO profile.** Gloves are consistent across all matches per the user's spec.

**Personality intent** (tuning targets, not code):
- **Tofu** — wild: larger amplitudes, longer periods, bouncier transitions.
- **Minty** — refined: moderate amplitudes, smooth (`TRANS_SINE`) transitions.
- **Sebastian** — efficient: small amplitudes, sharp (`TRANS_QUART`) transitions.

### D3 — Animation tech (Q2)

**Mixed approach.**

- **`_process(dt)` with `sin/cos`** drives continuous loops: opponent idle bob, player glove sway, opponent guard-dropped bounce. Reads amplitude/period from the profile (gloves use hardcoded constants).
- **`create_tween()`** drives transient one-shots: opponent attack lunge, hit recoil, knockdown fall (chained multi-phase), knockdown recover, player block snap, player punch throw. Profile supplies `Tween.TransitionType` per beat.
- **No AnimationPlayer.** Every beat is parameterized; AnimationPlayer would force runtime keyframe overrides, defeating the editor-authored advantage.

**Actor structure that falls out:**

- One `_continuous_mode` enum on the actor (`IDLE_BOB`, `GUARD_BOUNCE`, `GLOVE_SWAY`, `STILL`). `_process(dt)` reads it and writes `position`/`scale`/`rotation` deltas from a stored base transform.
- One `_current_tween: Tween` ref. Any new transient calls `_current_tween.kill()` then starts fresh. **Per-glove on `PlayerGloves`** (two refs) since gloves animate independently.
- Each actor stores its **base transform** (`_base_position`, `_base_scale`, `_base_rotation`) captured in `_ready()`. Continuous math and transient tweens both operate as deltas off this base, so cancellation can snap back cleanly.
- A **`_continuous_mode_t`** per-mode timer that resets to 0 on mode change — so beats like the guard bounce start cleanly at the planted position.

Rejected: all-Tween (marginally more code per loop, still needs kill-and-restart dance); AnimationPlayer (parameter-binding friction outweighs editor benefit).

### D4 — State preemption (Q3)

**Hard cancel.** Any incoming state change to either actor:

1. Calls `_current_tween.kill()` on the affected sprite (if alive).
2. Resets `position` / `scale` / `rotation` to the stored base transform for that sprite.
3. Dispatches the new state: starts a fresh transient tween, or sets `_continuous_mode` (picked up next `_process` tick).

**Per-glove independence.** `PlayerGloves` holds two `_current_tween` refs (one per glove sprite) because a left-glove punch can run concurrent with a right-glove block. The opponent has a single `_current_tween` ref since it's one sprite.

**Knockdown chain is the only multi-step transient.** `gameplay.gd` gates `KNOCK_DOWN_BANNER + KNOCKDOWN_PAUSE` around the fall, so nothing preempts mid-chain in practice. The hard-cancel rule still applies; it just doesn't fire there.

Rejected: soft cancel — would desync visuals from the authoritative dispatcher state.

## Per-beat decisions

### D5a — Player glove sway (Q4a)

Continuous loop driven by `_process(dt)` while both gloves are in `State.IDLE`. Constants in `player_gloves.gd`:

```gdscript
const SWAY_AMPLITUDE_X := 6.0
const SWAY_AMPLITUDE_Y := 4.0
const SWAY_PERIOD := 1.6
const SWAY_PHASE_OFFSET := PI  # right glove vs left glove
```

Each glove offset off its base position:

```
x_offset = SWAY_AMPLITUDE_X * sin(t * 2π / SWAY_PERIOD + phase)
y_offset = SWAY_AMPLITUDE_Y * sin(t * 2π / SWAY_PERIOD + phase + π/2)
```

Left glove `phase = 0`; right glove `phase = SWAY_PHASE_OFFSET`. Result is a small ellipse drift, gloves 180° out of phase ("breathing" feel).

### D5b — Player block beat (Q4b)

API change carried by D1. Block tweens BOTH gloves to per-direction poses. Bases: Left `(160, 920)`, Right `(1760, 920)`; canvas 1920×1080.

| Direction | Left glove target | Right glove target |
|---|---|---|
| **W** (head) | (160, 840) | (1760, 840) |
| **S** (body) | (400, 920) | (1520, 920) |
| **A** (opponent left hook) | (240, 920) | (1360, 920) |
| **D** (opponent right hook) | (560, 920) | (1680, 920) |

Both gloves swap texture to `block` for the duration. Out-tween easing: `TRANS_BACK` / `EASE_OUT` (snappy arrival with overshoot). Return-to-IDLE easing: `TRANS_QUAD` / `EASE_OUT` (cleaner retract). Sway resumes on return.

### D5c — Player punch beat (Q4c)

Only the punching glove animates and swaps texture; the other glove keeps its prior state. Per-direction targets:

| Direction | Glove | Target position | Target scale | Rotation |
|---|---|---|---|---|
| **A** | Left  | (700, 700)  | 0.65 | -15° |
| **D** | Right | (1220, 700) | 0.65 | +15° |
| **S** | Left  | (900, 780)  | 0.70 | -10° |
| **W** | Right | (1500, 500) | 0.55 | +20° |

Sign convention: Godot 2D rotates CW with positive radians. Spec uses degrees; convert with `deg_to_rad()` at use site.

**Two-phase chained tween:**
- Out-stroke: `position`, `scale`, `rotation` simultaneously to target. Easing `TRANS_BACK` / `EASE_OUT`.
- Return: chained immediately. Easing `TRANS_QUAD` / `EASE_IN`.

Texture: punching glove → `punch` for the duration; reverts to `idle` on return. Matches current behavior at `gameplay.gd:363/368`.

### D5d — Opponent idle bob (Q4d)

Continuous loop while `_continuous_mode == IDLE_BOB`. Math (offsets off the stored base transform):

```
x_offset = AMP_X * sin(t * 2π / PERIOD)
y_offset = -AMP_Y * cos(t * 2π / PERIOD)²
```

Two lift bumps per X cycle. Lift peaks at midline crossings (foot transfer); zero lift at X extremes (foot planted). Reads as boxer footwork.

Math shape is hardcoded — same shuffle for all three opponents. Personality differentiation comes through the numbers only.

### D5e — Opponent attack lunge (Q4e)

Direction-shift derivation in `opponent.gd`:

| Action | Direction | Gameplay dir | Shift |
|---|---|---|---|
| `SWING_HIGH` | `LEFT`  | W | +X |
| `SWING_MID`  | `LEFT`  | S | −X |
| `SWING_LOW`  | `LEFT`  | A | +X |
| `SWING_LOW`  | `RIGHT` | D | −X |

```gdscript
func _swing_shift(action, direction) -> float:
    match action:
        Action.SWING_HIGH: return +profile.attack_lunge_shift_x
        Action.SWING_MID:  return -profile.attack_lunge_shift_x
        Action.SWING_LOW:  return +profile.attack_lunge_shift_x if direction == Direction.LEFT else -profile.attack_lunge_shift_x
```

**Two-phase chained tween:**
- Out: `position.x += shift` and `scale *= peak` simultaneously. Easing `TRANS_BACK` / `EASE_OUT`.
- Return: chained back to base. Easing `TRANS_QUAD` / `EASE_IN`.

After the chain, the dispatcher calls `set_action(IDLE, ...)` and `_continuous_mode` switches back to `IDLE_BOB`. Ease types are hardcoded (`EASE_OUT` out, `EASE_IN` return); only transition type is profile-tunable.

### D5f — Opponent hit recoil + `Action.HIT_BODY` enum (Q4f)

**Enum addition.** `Action.HIT_BODY` is added between `HIT_HIGH` and `HIT_LOW`. Texture token resolves to `hit_low` (shares `body_hit_low.png` with existing `HIT_LOW`). Disambiguation is animation-only.

`HIT_LOW` semantics narrow to "side hit" (player A or D attack); mirror still via `Direction.LEFT/RIGHT`.

**Call site change.** `gameplay.gd:303` (`_hit_opponent_for`, BODY branch): `HIT_LOW` → `HIT_BODY`. One-line touch.

**Recoil shift derivation:**

```gdscript
func _recoil_shift(action, direction) -> float:
    match action:
        Action.HIT_HIGH: return +profile.hit_recoil_shift_x  # W → right
        Action.HIT_BODY: return -profile.hit_recoil_shift_x  # S → left
        Action.HIT_LOW:  return +profile.hit_recoil_shift_x if direction == Direction.LEFT else -profile.hit_recoil_shift_x
```

**Two-phase tween (scale inverted vs lunge):**
- Out (recoil): `position.x += shift` and `scale *= dip` simultaneously. Easing `TRANS_BACK` / `EASE_OUT`.
- Return (recover): chained back to base. Easing `TRANS_QUAD` / `EASE_IN`.

### D5g — Opponent knockdown fall + recovery (Q4g)

**Texture rule:** the `KNOCKED_DOWN` texture is shown for the **entire** knockdown sequence — from the moment the fall starts, through the held pose, through the recover motion. The swap back to `IDLE` happens at the **final frame of recover** ("stand again"). The `KNOCKED_DOWN` sprite art must read reasonably both standing-upright (frame 0 of fall) and lowered-tipped-small (held pose) — that's the artist's contract.

**Two new methods on `Opponent`:**

```gdscript
func play_knockdown_fall() -> void   # awaitable
func play_knockdown_recover() -> void # awaitable; non-KO only
```

**`play_knockdown_fall()` sequence:**

1. Snap texture to `KNOCKED_DOWN` (Direction.LEFT). Transform stays at base.
2. **Phase 1 — sway + shrink (parallel):**
   - `tween_method` drives `x_offset = sway_amplitude * sin(t * 2π * sway_cycles)` over `sway_duration`.
   - `tween_property` linearly scales from 1.0 down to `end_scale` over the same duration.
3. **Phase 2 — rotate + lower (parallel, chained after Phase 1):**
   - `rotation` → `rotation_degrees` (signed; negative = CCW).
   - `position.y` → `position.y + drop_y`.
   - Easing: `TRANS_QUAD` / `EASE_IN` (accelerating fall).
4. Method returns; `KNOCKED_DOWN` sprite sits at lowered+tipped+small transform.

**`play_knockdown_recover()` sequence (non-KO only):**

1. Parallel tween: `position`, `rotation`, `scale` back to base over `recover_duration`. Easing `TRANS_BACK` / `EASE_OUT` ("jumping up").
2. At tween finish: swap texture to `IDLE` (Direction.LEFT). `_continuous_mode` resumes `IDLE_BOB`.

**Updated `_play_knockdown_sequence` call site (lines 406-437):**

```
_snap_clear_simon_visuals()
_knockdowns.increment()
_refresh_knockdown_meter()
await _opponent.play_knockdown_fall()        # NEW
await _banner.show_banner("knock_down", KNOCK_DOWN_BANNER)
# remainder pause as today
if is_knockout():
    # KO branch — no recover; KNOCKED_DOWN holds through win banners → results
    ...
await _opponent.play_knockdown_recover()      # NEW
_clock.resume()
# fresh-start gap begins
```

`_opponent_idle()` at line 432 becomes redundant — `play_knockdown_recover` ends with `set_action(IDLE, LEFT)`. Drop the line or leave as a defensive no-op.

`KNOCKDOWN_PAUSE` budget may need to widen to absorb the pre-banner fall duration. That's a gameplay-side tweak covered by the deferred timing-pass note.

### D5h — Opponent guard-dropped bounce + `Action.GUARD_DOWN_EXCITED` enum (Q4h)

**Parse 1.** Bounce runs from the initial guard-drop until the first player hit lands. After the first hit, opponent stays in plain `GUARD_DOWN` (no bounce) for the rest of attack phase.

**Enum addition.** `Action.GUARD_DOWN_EXCITED` is added. Texture token resolves to `guard_down` (shares `body_guard_down.png`). Disambiguation is animation-only.

**Call site change.** `gameplay.gd:344` (initial guard-drop on right-answer riddle): `GUARD_DOWN` → `GUARD_DOWN_EXCITED`. Line 372 (post-hit return) keeps plain `GUARD_DOWN`. One-line touch at 344.

**Bounce math** (continuous loop, `_process()`-driven, mode = `GUARD_BOUNCE`):

```
x_offset = 0
y_offset = -guard_bounce_amplitude_y * (1 - cos(t_mode * 2π / guard_bounce_period)) / 2
```

Always above base (y_offset ≤ 0 in Godot Y-down). One peak per period — "boxer hopping in place" feel.

The `_continuous_mode_t` per-mode timer (introduced in D3) ensures the bounce starts at the planted position (y=0) when entering `GUARD_BOUNCE` mode.

## Scope decisions

### D6 — Consolidated profile + player constants (Q5)

See **Implementation Reference** at the bottom of this spec.

### D7 — Minty/Sebastian tuning deferred (Q6)

Ship Tofu's profile tuned; Minty and Sebastian fall back to Tofu's via `animation_profile_path = ""` on their `DifficultyConfig` — same fallback pattern as `dialogue_deck_path`.

Tuning Minty's "refined" personality and Sebastian's "efficient" personality is a follow-up effort. Tuning three profiles in parallel triples playtest-loop blocking; ship Tofu, validate the framework, then tune the others with fresh eyes.

### D8 — Scope decomposition + branch (Q7 + Q9)

**One branch, five sequential commits, each playable end-to-end.** Branch: `feature/actor-animations`, cut from `main` after pulling.

| # | Title | Ships | Testable after |
|---|---|---|---|
| 1 | Idle continuous loops | `OpponentAnimationProfile` type + Tofu `.tres` + `DifficultyConfig.animation_profile_path` + fallback + base-transform/`_continuous_mode`/`_current_tween`/`_continuous_mode_t` plumbing on both actors + opponent idle bob + player glove sway | Opponent bobs in stance; gloves sway. Block/attack still snap (no transients yet). All three opponents work via fallback. |
| 2 | Player block + punch tweens | Glove API change `set_state(state, direction)` + 4 call-site updates in `gameplay.gd` + block tween (both gloves, 4 directions) + punch tween (one glove, 4 directions) | Blocks snap both gloves into per-direction poses; punches shrink/rotate toward target. |
| 3 | Opponent lunge + recoil | `Action.HIT_BODY` enum + `gameplay.gd:303` one-line update + attack-lunge tween + hit-recoil tween + `_swing_shift`/`_recoil_shift` helpers | Opponent lunges on swings; recoils on every hit. |
| 4 | Guard-dropped bounce | `Action.GUARD_DOWN_EXCITED` enum + `gameplay.gd:344` one-line update + guard-bounce continuous loop | Attack-phase entry: opponent bounces in anticipation. First hit stops bounce. |
| 5 | Knockdown fall + recover | `play_knockdown_fall()` + `play_knockdown_recover()` methods + `_play_knockdown_sequence` reshape + KNOCKDOWN_PAUSE budget widening if needed | Knockdown plays multi-phase fall; non-KO pops back up; KO stays down through win banners. |

Each commit boots, plays, and demonstrates a visible improvement. Bisectable. Increment 1 lands all shared infrastructure; #2-5 are purely additive.

No per-increment PRs unless preferred — one branch, one final PR with five commits is the default.

The deferred timing-tuning pass is a separate effort after all 5 land.

## Implementation Reference

### `OpponentAnimationProfile` (Resource) — 24 fields

```gdscript
class_name OpponentAnimationProfile
extends Resource

# Idle bob (continuous)
@export var idle_bob_amplitude_x: float = 22.0
@export var idle_bob_amplitude_y: float = 10.0
@export var idle_bob_period: float = 1.1

# Attack lunge (transient, two-phase)
@export var attack_lunge_shift_x: float = 40.0
@export var attack_lunge_scale_peak: float = 1.10
@export var attack_lunge_out_duration: float = 0.12       # starting estimate
@export var attack_lunge_return_duration: float = 0.15    # starting estimate
@export var attack_lunge_transition_out: int = Tween.TRANS_BACK
@export var attack_lunge_transition_return: int = Tween.TRANS_QUAD

# Hit recoil (transient, two-phase, scale inverted vs lunge)
@export var hit_recoil_shift_x: float = 40.0
@export var hit_recoil_scale_dip: float = 0.92
@export var hit_recoil_out_duration: float = 0.10         # starting estimate
@export var hit_recoil_return_duration: float = 0.15      # starting estimate
@export var hit_recoil_transition_out: int = Tween.TRANS_BACK
@export var hit_recoil_transition_return: int = Tween.TRANS_QUAD

# Knockdown fall (transient, multi-phase)
@export var knockdown_fall_sway_amplitude: float = 30.0
@export var knockdown_fall_sway_cycles: float = 1.5
@export var knockdown_fall_sway_duration: float = 0.8     # starting estimate
@export var knockdown_fall_end_scale: float = 0.7
@export var knockdown_fall_rotation_degrees: float = -40.0
@export var knockdown_fall_drop_y: float = 200.0
@export var knockdown_fall_drop_duration: float = 0.3     # starting estimate
@export var knockdown_fall_drop_transition: int = Tween.TRANS_QUAD

# Knockdown recover (transient, non-KO only)
@export var knockdown_recover_duration: float = 0.3       # starting estimate
@export var knockdown_recover_transition: int = Tween.TRANS_BACK

# Guard-dropped bounce (continuous, GUARD_DOWN_EXCITED only)
@export var guard_bounce_amplitude_y: float = 18.0
@export var guard_bounce_period: float = 0.45
```

Field count: 16 floats + 6 `Tween.TransitionType` ints + 2 cycle/scale modifiers = 24. Ease types are hardcoded (always `EASE_OUT` on out-stroke, `EASE_IN` on return) — not part of the profile.

### Player-side constants (in `player_gloves.gd`)

```gdscript
# Idle sway (continuous, both gloves)
const SWAY_AMPLITUDE_X := 6.0
const SWAY_AMPLITUDE_Y := 4.0
const SWAY_PERIOD := 1.6
const SWAY_PHASE_OFFSET := PI

# Block targets — per WASD direction (both gloves move)
const BLOCK_TARGETS := {
    SimonSequence.Direction.HEAD:  { "left": Vector2(160, 840),  "right": Vector2(1760, 840) },
    SimonSequence.Direction.BODY:  { "left": Vector2(400, 920),  "right": Vector2(1520, 920) },
    SimonSequence.Direction.LEFT:  { "left": Vector2(240, 920),  "right": Vector2(1360, 920) },
    SimonSequence.Direction.RIGHT: { "left": Vector2(560, 920),  "right": Vector2(1680, 920) },
}
const BLOCK_OUT_DURATION := 0.10       # starting estimate
const BLOCK_RETURN_DURATION := 0.15    # starting estimate
const BLOCK_OUT_TRANSITION := Tween.TRANS_BACK
const BLOCK_RETURN_TRANSITION := Tween.TRANS_QUAD

# Punch targets — per WASD direction (only the punching glove moves)
const PUNCH_TARGETS := {
    SimonSequence.Direction.LEFT:  { "glove": Side.LEFT,  "pos": Vector2(700, 700),  "scale": 0.65, "rotation_deg": -15.0 },
    SimonSequence.Direction.RIGHT: { "glove": Side.RIGHT, "pos": Vector2(1220, 700), "scale": 0.65, "rotation_deg": +15.0 },
    SimonSequence.Direction.BODY:  { "glove": Side.LEFT,  "pos": Vector2(900, 780),  "scale": 0.70, "rotation_deg": -10.0 },
    SimonSequence.Direction.HEAD:  { "glove": Side.RIGHT, "pos": Vector2(1500, 500), "scale": 0.55, "rotation_deg": +20.0 },
}
const PUNCH_OUT_DURATION := 0.10       # starting estimate
const PUNCH_RETURN_DURATION := 0.15    # starting estimate
const PUNCH_OUT_TRANSITION := Tween.TRANS_BACK
const PUNCH_RETURN_TRANSITION := Tween.TRANS_QUAD
```

### Existing `gameplay.gd` call sites that change

```
236: _gloves.set_state(side, PlayerGloves.State.BLOCK)
     →  _gloves.set_state(PlayerGloves.State.BLOCK, direction)
238: _gloves.set_state(side, PlayerGloves.State.IDLE)
     →  _gloves.set_state(PlayerGloves.State.IDLE)
303: action = Opponent.Action.HIT_LOW    [BODY branch]
     →  action = Opponent.Action.HIT_BODY
325-327: _snap_clear_simon_visuals — drop the per-side IDLE calls, single IDLE call
344: _opponent.set_action(Opponent.Action.GUARD_DOWN, ...)
     →  _opponent.set_action(Opponent.Action.GUARD_DOWN_EXCITED, ...)
363: _gloves.set_state(side, PlayerGloves.State.PUNCH)
     →  _gloves.set_state(PlayerGloves.State.PUNCH, direction)
368: _gloves.set_state(side, PlayerGloves.State.IDLE)
     →  _gloves.set_state(PlayerGloves.State.IDLE)
406-437: _play_knockdown_sequence — reshape per D5g (add await play_knockdown_fall, add await play_knockdown_recover for non-KO)
```

### Scene geometry (1920×1080 canvas)

- `Opponent` Node2D at `(960, 400)`. `Body` Sprite2D child at offset `(0, 230)` with `scale = (0.85, 0.85)`. Sprite renders centered at roughly `(960, 630)`.
- `PlayerGloves` Node2D has no transform. `LeftGlove` Sprite2D at `(160, 920)`, `RightGlove` Sprite2D at `(1760, 920)` — bottom corners of the canvas.

## Implementation steps

1. ✅ Spec written (this file).
2. ✅ CONTEXT.md updated with the new "Visual Behavior" section, Shift Map, Animation Profile rules, and the two enum-disambiguation notes in the asset table + mirroring rules.
3. ✅ Plan written at `docs/superpowers/plans/2026-05-19-actor-animations.md`.
4. Pull `main`, cut branch `feature/actor-animations`.
5. Hand off to subagent-driven-development for implementation, increment by increment.

## Executor notes

- The user is in feedback/polish phase of an MVP that's been verified end-to-end. They are NOT looking for new milestones; they queue iterative changes.
- CLAUDE.md says: don't add error handling / validation for scenarios that can't happen; trust internal code; YAGNI on speculative features. Apply when scoping animation safety checks.
- **Godot binary on macOS causes dock-icon focus flash even with `--headless`.** Hold Godot invocations to an absolute minimum during animation development. Animations are visual; unit tests won't catch animation correctness anyway — lean on user playtest.
- **Each increment must be user-testable end-to-end** (per feedback memory). No scaffolding-only commits that leave the running game in a broken or non-playable state.
- **Parity check** when finishing each increment: Player vs Opponent integration with `gameplay.gd` — ensure no call site was missed (per feedback memory).
