# Carousel 3D Orbit + Glove Punch Design

**Date:** 2026-05-23
**Status:** Approved for plan-writing
**Builds on:** [ADR-0001 — Riddle Answer Carousel positioning seam](../../adr/0001-riddle-answer-carousel-positioning.md), PR #14 (Answer Carousel implementation)

---

## Goal

Replace the in-riddle-box flat carousel with a free-floating diagonal-tilted answer cluster in the upper-right play area. On K-confirm, the right glove punches the chosen card, the card flies into the opponent, and the opponent reacts with `body_hit_low` then settles to `guard_down`. This is the Phase C upgrade ADR-0001 anticipated, plus a new spatial relationship between the carousel, the right glove, and the opponent.

## Motivation

The current carousel (PR #14) sits inside the riddle box, centered at the bottom of the screen. The right glove rests at (1760, 920) — ~800px away from the center card — so any glove-touches-card animation requires a huge sweep that doesn't read as a punch. Pulling the cards out of the riddle box and floating them in the upper-right play area puts them inside the right glove's natural punch arc, and the diagonal tilt aligns the cards along the same trajectory the punch takes into the opponent. The riddle text stays exactly where it is.

## Out of scope

- Left-glove punch variants (the chosen card is always the center slot; one glove handles all confirms — chosen here as the right glove because the cluster is to the right of center).
- Tuning-pass adjustments to the new constants — those happen post-implementation per the established playtest convention.
- Changes to the I-no-op rule, J/L wrap behavior, queue-depth-1, K-during-rotation/typewriter/fade gates — these contracts carry forward unchanged.
- Changes to the existing Simon attack-phase glove punches — `PlayerGloves.PUNCH_TARGETS` stays untouched.
- Changes to the body-text typewriter, render gate, or NEUTRAL re-display path inside RiddleBox.

---

## Architecture

### New scene + script

**`scenes/ui/answer_carousel.tscn`** — root `Control` containing three `AnswerCard` child instances, absolutely positioned by script.

**`scripts/ui/answer_carousel.gd`** owns:
- Cards array, `_highlight_index`, `_picked_answers`
- Carousel layout constants (slot anchors, scales, z-orders, all animation durations)
- The ADR-0001 transform seam: `_compute_card_transform`, `_make_position`, `_slot_anchor`, `_slot_role_for`, `_slot_scale`, `_slot_z`
- `_rotation_state` dict + rotation tween + queue depth 1
- Fade-in tween (`_is_fading_in`, `_fade_tween`)
- Exit tween (`_exit_tween`)
- **NEW:** punch choreography state (`_is_punching`, glove tween, card-flight tween, card-flash tween)
- **NEW:** 3D-orbit Vector2 anchor math
- J/L/K input handling (moves out of `RiddleBox._unhandled_input`)
- Signals: `answer_submitted(outcome, picked_answer)`, `card_struck_opponent(direction)`

### RiddleBox shrinks

`scripts/ui/riddle_box.gd` retains:
- `display(prompt)` — body text + typewriter + image-body branch
- `display_instant(prompt)` — synchronous body text
- `is_rendering()`, `body_render_complete` signal
- `show_reaction(reaction_text)` — reaction typewriter only. The empty-reaction (Tofu) case is detected by the caller checking `picked.reaction_text == ""` (or `picked.has_reaction()`); if empty, the caller invokes `RiddleBox.hide()` instead of `show_reaction`. `RiddleBox` itself no longer reaches into a `_picked_answers` array — it only handles text it's given.
- Body image / body text visibility handling

RiddleBox loses: `_cards`, `_highlight_index`, `_picked_answers`, all `_slot_*` helpers, `_compute_card_transform`, `_make_position`, `_rotation_state`, all carousel tweens (`_rotation_tween`, `_fade_tween`, `_exit_tween`), all carousel input handling, the entire `_unhandled_input` method.

`scenes/ui/riddle_box.tscn` loses the `Layout/Answers` Control and its three card children. `Layout` becomes a single-child VBox (or collapses to no VBox).

### gameplay.tscn additions

A new `AnswerCarousel` Control instance, sibling of `RiddleBox`, positioned with its container origin near `(1280, 410)` on the 1920×1080 stage. Exact constants tuned during playtest.

### gameplay.gd re-wiring

- `@onready var _carousel: AnswerCarousel = $AnswerCarousel` alongside the existing `_riddle`.
- On prompt display: calls both `_riddle.display(prompt)` and `_carousel.display_prompt(prompt)` together.
- `answer_submitted` is now emitted by `AnswerCarousel`. The existing `_on_answer_submitted` handler keeps its signature; only the connect-site changes.
- A new `card_struck_opponent(direction)` signal from the carousel routes to `Opponent.set_action(HIT_LOW, direction)` followed by a queued `set_action(GUARD_DOWN)` after `HIT_HOLD_DURATION`.
- The render gate stays: `AnswerCarousel` listens for `RiddleBox.body_render_complete` and triggers its own fade-in. Image-body prompts (Tofu) skip the fade on both sides as today.

### CONTEXT.md updates (during Phase 1 of implementation)

The `Riddle Box + Answer Cards UI Region` section is split into `Riddle Box UI Region` (body text only) and `Answer Carousel UI Region` (the floating cluster). The `Reaction State` and `Riddle Encounter` sections are updated to describe the new choreography. The `IJKL vocabulary` block is unchanged.

---

## Visual layout & 3D orbit math

### Carousel container position

A `Control` positioned at roughly `(1280, 410)` on the 1920×1080 stage — upper-right, between the opponent's silhouette and the right edge, above and right of the riddle box. The container holds the three cards as absolutely-positioned children. Exact center tuned during playtest.

### Slots become Vector2 anchors

The five logical slots (OFF_LEFT, SIDE_LEFT, CENTER, SIDE_RIGHT, OFF_RIGHT) now have Vector2 anchors expressed as offsets from the container origin:

```gdscript
const CENTER_ANCHOR     := Vector2(0, 0)
const SIDE_LEFT_ANCHOR  := Vector2(-SIDE_OFFSET.x,  SIDE_OFFSET.y)  # down-and-left
const SIDE_RIGHT_ANCHOR := Vector2( SIDE_OFFSET.x, -SIDE_OFFSET.y)  # up-and-right
const OFF_LEFT_ANCHOR   := Vector2(-OFF_SCREEN_OFFSET.x,  OFF_SCREEN_OFFSET.y)
const OFF_RIGHT_ANCHOR  := Vector2( OFF_SCREEN_OFFSET.x, -OFF_SCREEN_OFFSET.y)
```

Starting values: `SIDE_OFFSET = Vector2(140, 90)` (about 33° axis tilt off horizontal), `OFF_SCREEN_OFFSET = Vector2(420, 270)` (same axis, far enough that the displaced card is visibly out of the cluster before re-entering). All starting values; tuned post-implementation.

### Card layout

- L card (lower-left): `SIDE_LEFT_ANCHOR`, scale `SIDE_SCALE = 0.7`, z `SIDE_Z = 0`
- M card (center): `CENTER_ANCHOR`, scale `CENTER_SCALE = 1.0`, z `CENTER_Z = 10`
- R card (upper-right): `SIDE_RIGHT_ANCHOR`, scale `SIDE_SCALE = 0.7`, z `SIDE_Z = 0`

Cards stay flat-facing — no yaw rotation. The 3D feel comes entirely from the diagonal layout + perspective scale + z-ordered overlap. Overlap is intentional: with `SIDE_OFFSET.x = 140` and card-half-width × `SIDE_SCALE` ≈ 100, the side card encroaches ~60px onto the center card, sitting behind it visually.

### Transform seam: Vector2-native

`_compute_card_transform(card_index, rotation_state)` still returns `{position, scale, z}`. Internal changes:
- `_slot_anchor(slot) -> Vector2` (was `_slot_anchor_x(slot) -> float`)
- Non-wrap path: `anchor = lerp(_slot_anchor(from_role), _slot_anchor(to_role), progress)` — pure Vector2 lerp
- Wrap path (SIDE_LEFT ↔ SIDE_RIGHT through off-screen): two-segment piecewise teleport, same shape as today, each segment lerps Vector2 anchors instead of float X
- `_make_position(anchor: Vector2) -> Vector2` returns `Vector2(anchor.x - CARD_WIDTH/2.0, anchor.y - CARD_HEIGHT/2.0)` — converts slot-center anchor to card top-left
- Scale lerp unchanged conceptually (raw `progress`, with the existing coupling comment carried forward)

ADR-0001's seam discipline is preserved: every position computation routes through `_make_position`, including the exit tween's off-screen target.

---

## Punch choreography

### Timing diagram (seconds from K-press)

```
t=0.00 → K accepted by AnswerCarousel
         Gates clear: not REACTION, not _is_rendering,
                      not _is_fading_in, not _is_rotating, not _is_punching
         _is_punching = true  (locks all carousel input)
         SFX  swing.wav
         GLOVE  right glove tweens from rest (1760, 920)
                → chosen card's screen position
                duration GLOVE_TRAVEL_DURATION = 0.15s
                easing TRANS_BACK ease-out

t=0.15 → IMPACT FRAME (glove reaches card)
         SFX  opponent_punch_body (random from 1..10 pool)
         SFX  menu_option_select
         CARD  picked card flashes — modulate spike to white, decay CARD_FLASH_DURATION = 0.08s
         CARDS side cards begin existing exit tween
               (slide to off-screen wrap anchors + fade alpha to 0)
         CARD  picked card begins flight tween
               target: opponent body global_position
               duration CARD_FLIGHT_DURATION = 0.20s
               scale 1.0 → CARD_FLIGHT_END_SCALE (0.4)
               alpha 1.0 → 0 (fades just before impact)
         TEXT  if picked.has_reaction():
                   RiddleBox.show_reaction(picked.reaction_text)  → reaction typewriter starts
               else:
                   RiddleBox.hide()                                → Tofu empty-reaction path
         SIG   AnswerCarousel.answer_submitted(outcome, picked_answer) emits
               → gameplay._on_answer_submitted plays outcome SFX (riddle_correct/_neutral/_wrong)
                 + queues next phase

t=0.35 → CARD HITS OPPONENT (card-flight tween finishes)
         SFX  opponent_punch_body (random from pool, 2nd play)
         OPP  Opponent.set_action(HIT_LOW, Direction.RIGHT)
              (flip_h=true so opponent rolls right with the card coming from screen-right)
         CARD picked card hidden (alpha 0 reached, set visible=false)
         GLOVE right glove begins return tween to rest (parallel)
               duration PUNCH_RETURN_DURATION = 0.30s (existing constant)

t=0.60 → HIT_HOLD complete (HIT_HOLD_DURATION = 0.25s after card impact)
         OPP  Opponent.set_action(GUARD_DOWN)  (default direction, flip_h=false)
         _is_punching = false
         All 3 cards now off-screen or hidden — carousel awaits next display_prompt
```

### Right glove integration

`PlayerGloves` gets one new public method:

```gdscript
func punch_at_screen_position(target_pos: Vector2) -> void
```

The method animates the right glove to `target_pos` over `GLOVE_TRAVEL_DURATION` with `TRANS_BACK` ease-out (matching existing Simon punch feel), swaps to the PUNCH texture, fires the return tween over `PUNCH_RETURN_DURATION` at impact, and resumes IDLE sway.

The existing `PUNCH_TARGETS` dict and Simon-attack-phase code paths are untouched.

### Card-flight target

The opponent's body position is queried via `Opponent.get_node("Body").global_position` (Sprite2D in opponent scene). The card flight target = body's global position + a small offset to land on the mid-body (not the head). Coordinate translation between Control-space (cards) and Node2D-space (opponent) is handled by `to_global`/`to_local` as needed; both ultimately resolve to viewport-screen Vector2 for the tween.

### Signals

- `AnswerCarousel.answer_submitted(outcome, picked_answer)` — emits at IMPACT FRAME. Carries the picked `DialogueAnswer` so gameplay can read outcome + queue reaction text.
- `AnswerCarousel.card_struck_opponent(direction)` — emits at t=0.35 (card-flight finish). Gameplay forwards to `Opponent.set_action(HIT_LOW, direction)`. Keeping it as a signal lets the carousel stay opponent-agnostic.

### Input-gate matrix

The carousel's `_unhandled_input` adds `_is_punching` to its early-return guards alongside the existing `_is_rendering` and `_is_fading_in` gates.

| Gate | Blocks J/L | Blocks K |
|---|---|---|
| `_state == REACTION` (RiddleBox state mirror) | yes | yes |
| `_is_rendering` (body typewriter active) | yes | yes |
| `_is_fading_in` (carousel fade-in active) | yes | yes |
| `_is_rotating` (J/L rotation tween) | no (queued depth-1) | yes |
| `_is_punching` (NEW — punch chain in flight) | yes | yes |

---

## New tunable constants

All in `answer_carousel.gd`, in one block per the project's playtest convention:

```gdscript
# Layout
const SIDE_OFFSET           := Vector2(140, 90)
const OFF_SCREEN_OFFSET     := Vector2(420, 270)
const SIDE_SCALE            := 0.7
const CENTER_SCALE          := 1.0
const CENTER_Z              := 10
const SIDE_Z                := 0

# Animation timings (carried from PR #14)
const ROTATION_DURATION     := 0.18
const FADE_IN_DURATION      := 0.15
const EXIT_DURATION         := 0.18

# Punch choreography (NEW)
const GLOVE_TRAVEL_DURATION := 0.15
const CARD_FLIGHT_DURATION  := 0.20
const HIT_HOLD_DURATION     := 0.25
const CARD_FLASH_DURATION   := 0.08
const CARD_FLIGHT_END_SCALE := 0.4
```

The carousel container position in `gameplay.tscn` is a separate scene-level constant (not in the script's tuning block) but is also tuned post-implementation.

---

## Testing strategy

### test_riddle_box.gd — slimmed

Drops card-visibility, fade, carousel-input tests. Keeps:
- `display()` runs typewriter, emits `body_render_complete`
- `display_instant()` shows full text synchronously
- `display()` is awaitable, resolves after typewriter
- Image-body prompts skip typewriter
- `show_reaction(reaction_text)` starts reaction typewriter and transitions to REACTION state
- Empty-reaction case hides the box
- K-suppression during typewriter (integration test — may need to mount AnswerCarousel too to verify the gate routing)

### test_answer_carousel.gd — NEW (replaces test_riddle_box_carousel.gd)

Carries over all 13 carousel tests with assertions updated for Vector2 positions and the new container origin:
- J decrements highlight with wrap (3 tests in PR #14)
- L increments highlight with wrap
- I is no-op
- Layout: center at full scale, sides at SIDE_SCALE
- Cycle swaps which card is at center
- Two rapid presses land on target via queue
- Third input during rotation is dropped
- K during rotation is rejected
- Cards invisible during typewriter
- Cards fade to full opacity after typewriter
- display_instant skips fade
- J/L locked during fade-in
- Unpicked cards animate out on confirm (with alpha + position)

Plus new tests:
- **3D orbit layout:** `SIDE_LEFT_ANCHOR.x < 0 and SIDE_LEFT_ANCHOR.y > 0` (lower-left); `SIDE_RIGHT_ANCHOR` mirrored; CENTER at origin
- **Vector2 transform interpolation:** `_compute_card_transform` at intermediate `progress` produces correct Vector2 (not just X)
- **Wrap traverses both axes:** wrap path goes through off-screen on both X and Y
- **`_is_punching` gates all input:** during punch, J/L/K all rejected
- **K triggers punch sequence:** `swing` SFX fires, `_is_punching` flips true, glove tween starts
- **IMPACT FRAME beats:** `opponent_punch_body` + `menu_option_select` both play, picked card flash modulate spikes, side-card exit tween starts, picked-card flight tween starts, `answer_submitted` emits with outcome + picked_answer, `RiddleBox.show_reaction` called with the right text
- **`card_struck_opponent` signal:** emits at flight-end with `Direction.RIGHT`
- **HIT_HOLD timing:** `_is_punching` clears `HIT_HOLD_DURATION` after card impact
- **Empty-reaction (Tofu) path:** punch chain still plays; `RiddleBox.hide()` called instead of `show_reaction`

### test_player_gloves.gd — extended

New tests for `punch_at_screen_position(target)`:
- Glove tweens to target over `GLOVE_TRAVEL_DURATION` with TRANS_BACK ease-out
- PUNCH texture loaded during travel
- Returns to rest via existing PUNCH_RETURN_DURATION + transition
- Existing `PUNCH_TARGETS`-based tests (Simon attack flow) untouched

### SFX assertions

The project's `AudioBus` autoload is the SFX surface. Tests either stub it or use a spy that records `play_sfx(name)` calls. The pattern depends on what's already in `test_riddle_box.gd`; implementation matches the established convention.

---

## Rollout

Four phases, each playable, single branch + single PR (matches the PR #14 cadence). After all four land, a tuning pass adjusts the new constants based on playtest feel.

### Phase 1 — Extraction

Carousel logic moves from `riddle_box.gd` → `answer_carousel.gd`. New `answer_carousel.tscn`. `gameplay.tscn` adds the carousel as a sibling of `RiddleBox`. **Layout unchanged** — cards still appear in the old centered position (the carousel container's initial offset places it where the old `Layout/Answers` Control was). Tests migrate. CONTEXT.md updated.

Playable result: identical to today's behavior. Validates the extraction works before anything else changes.

### Phase 2 — Reposition + 3D orbit

Move carousel container to upper-right (~(1280, 410)). Switch slot anchors to Vector2 with diagonal-tilt `SIDE_OFFSET`. Update `_compute_card_transform` and `_make_position` for Vector2 math. New Vector2-position tests added.

Playable result: cards float in upper-right with the diagonal-tilt layout, overlapping per the screenshot. K still works as today (snap-hide / existing exit tween — punch chain not yet added).

### Phase 3 — Glove travel + impact frame

Add `_is_punching` gate. K triggers `PlayerGloves.punch_at_screen_position(card.global_position)`. On impact: SFX pair, card flash, picked-card flight tween starts toward a **placeholder** screen position (e.g., centered just above the riddle box). `answer_submitted` emits at impact instead of at K-press. New choreography tests added.

Playable result: visible punch sequence — glove punches, card flies "somewhere" (placeholder target). Side-card exit and reaction text both kick off at impact.

### Phase 4 — Opponent hit-reaction

Card-flight target = opponent body global_position. `card_struck_opponent` signal fires at flight end. Gameplay forwards to `Opponent.set_action(HIT_LOW, Direction.RIGHT)` then `set_action(GUARD_DOWN)` after `HIT_HOLD_DURATION`. Opponent-signaling test added.

Playable result: full chain — card lands on opponent, body_hit_low (mirrored), guard_down transition.

### Final tuning pass

Adjust the constants (SIDE_OFFSET, OFF_SCREEN_OFFSET, GLOVE_TRAVEL_DURATION, CARD_FLIGHT_DURATION, HIT_HOLD_DURATION, CARD_FLASH_DURATION, CARD_FLIGHT_END_SCALE, carousel container position) per playtest feel. Single commit at the end of the branch if needed.

---

## Reference

- Plan precedent: [PR #14 / Riddle Answer Carousel plan](../plans/2026-05-23-riddle-answer-carousel.md)
- Architectural seam: [ADR-0001](../../adr/0001-riddle-answer-carousel-positioning.md)
- Glove patterns: `scripts/actors/player_gloves.gd` (existing PUNCH_TARGETS, tween-glove-to helper)
- Opponent action API: `scripts/actors/opponent.gd::set_action(action, direction)`
- SFX pool: `assets/audio/sfx/` (swing.wav, opponent_punch_body_01..10.wav, menu_option_select.wav, riddle_correct/_neutral/_wrong)
