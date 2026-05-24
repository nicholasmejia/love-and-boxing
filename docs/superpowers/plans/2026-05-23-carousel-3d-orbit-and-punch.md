# Carousel 3D Orbit + Glove Punch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the answer carousel from `RiddleBox` into a free-floating diagonal-tilted cluster in the upper-right play area, then choreograph a K-confirm punch chain (right glove → chosen card → opponent body → guard down).

**Architecture:** Four phases on a single branch (`feature/carousel-3d-orbit-and-punch`), one PR. Phase 1 extracts the carousel (`scripts/ui/answer_carousel.gd` + `scenes/ui/answer_carousel.tscn`) and slims `RiddleBox` to body-only, with the layout unchanged. Phase 2 swaps slot anchors to `Vector2`, applies the diagonal tilt (L lower, R higher), and repositions the container to the upper-right. Phase 3 adds the right-glove punch tween + impact-frame work (`opponent_punch_body` + `menu_option_select` SFX, card flash, picked-card flight toward a placeholder target). Phase 4 wires the picked card's flight target to the opponent's body global position, emits `card_struck_opponent`, and the opponent reacts `body_hit_low` (mirrored) → `guard_down`. Final tuning pass + PR.

**Tech Stack:** Godot 4.6 (Control + Tween + Node2D), GDScript, GUT 9.x for unit tests. Visual feel (tilt angle, container position, all new durations) is manually playtested per the project's "user is the test harness for visual/feel work" convention; exposed as tuning constants in `answer_carousel.gd`.

**Prerequisite:** This plan assumes [PR #14 — Riddle Answer Carousel](https://github.com/nicholasmejia/love-and-boxing/pull/14) has merged to `main`. Phase 1 extracts code that PR #14 introduced; without that merge, `scripts/ui/riddle_box.gd` has no carousel code to extract. If PR #14 is still open when execution begins, the executor should rebase this branch onto the merged main first: `git rebase main`.

**Reference docs:**
- `docs/superpowers/specs/2026-05-23-carousel-3d-orbit-and-punch-design.md` — design doc (commit `be10338`)
- `docs/adr/0001-riddle-answer-carousel-positioning.md` — the seam discipline this plan honors
- `CONTEXT.md` — current sections on Riddle / Render Gate / Reaction State / Riddle Encounter / Riddle Box / Answer Cards UI Region (all touched in Task 1)

---

## File Structure

**Creates:**
- `scripts/ui/answer_carousel.gd` — extracted carousel logic + new 3D-orbit math + punch choreography
- `scenes/ui/answer_carousel.tscn` — new scene with three `AnswerCard` children (absolutely positioned by script)
- `tests/unit/test_answer_carousel.gd` — port of `test_riddle_box_carousel.gd` + new tests

**Modifies:**
- `scripts/ui/riddle_box.gd` — shrinks from ~411 lines to ~100 lines (body text + typewriter + render gate + reaction-text-only)
- `scenes/ui/riddle_box.tscn` — removes `Layout/Answers` Control and its three card children
- `scenes/gameplay.tscn` — adds `AnswerCarousel` as a sibling of `RiddleBox`
- `scripts/gameplay.gd` — re-wires `answer_submitted` signal to carry `(outcome, picked_answer)` from the carousel, routes reaction-text/hide to RiddleBox
- `scripts/actors/player_gloves.gd` — adds `punch_at_screen_position(target_pos)` for Phase 3
- `tests/unit/test_riddle_box.gd` — drops carousel-related tests, updates `show_reaction` test for the new string-arg signature
- `tests/unit/test_player_gloves.gd` — adds tests for `punch_at_screen_position`
- `scripts/actors/opponent.gd` — no public API changes; Phase 4 just calls the existing `set_action(action, direction)` from `gameplay.gd`
- `CONTEXT.md` — splits the Riddle Box + Answer Cards UI Region into two regions; updates Render Gate / Reaction State / Riddle Encounter

**Deletes:**
- `tests/unit/test_riddle_box_carousel.gd` (replaced by `test_answer_carousel.gd`)
- `tests/unit/test_riddle_box_carousel.gd.uid` (Godot import artifact; sibling of the deleted .gd)

---

## Task 1: Lock in CONTEXT.md for the new architecture

Update the glossary so the spec is reflected in the canonical project doc *before* any code changes. Mirrors PR #14's Task 1 pattern.

**Files:**
- Modify: `CONTEXT.md` (sections: Riddle / Dialogue Prompt, Riddle Render Gate, Reaction State, Riddle Encounter, UI Regions / Riddle Box, UI Regions / Answer Cards)

- [ ] **Step 1: Update the "Riddle Render Gate" section**

In `CONTEXT.md`, find the line starting with `- **Riddle Render Gate** —` (currently line 15). It currently says the Answer Carousel is hidden during typewriter inside RiddleBox. Update the sentence that begins "The **Answer Carousel** is hidden during the typewriter portion..." so it reads:

```
The **Answer Carousel** (a sibling UI node in `gameplay.tscn`, not a child of RiddleBox) is hidden during the typewriter portion (cards are not rendered at all) and fades in once the typewriter completes — it listens for `RiddleBox.body_render_complete` to trigger the fade. All carousel input (`menu_left` / `menu_right` cycling and `menu_confirm`) is gated behind the fade-in completing — there is no pre-positioning during typewriter. Image-body prompts (Tofu) and the NEUTRAL re-display path (`RiddleBox.display_instant()`) skip the typewriter and the fade — the carousel is operable the frame the prompt is shown.
```

- [ ] **Step 2: Rewrite the "Reaction State" section**

Find the line starting with `- **Reaction State** —` (currently line 16). Replace its body with:

```
Post-answer beat that runs inside the existing Riddle Gap. K-confirm triggers a punch choreography: the right glove tweens to the chosen card (~150ms, `swing` SFX), the card flashes white on impact (`opponent_punch_body` + `menu_option_select` SFX), the two unpicked cards animate out (slide to off-screen wrap positions + fade to transparent), and the picked card flies toward the opponent's body (~200ms, scale 1.0→0.4, alpha 1.0→0). At impact-frame, the body area renders the picked `DialogueAnswer.reaction_text` via the same typewriter used for prompt bodies, and `answer_submitted(outcome, picked_answer)` emits so gameplay can fire the outcome SFX and queue the next phase. When the picked card hits the opponent body (~350ms after K), `card_struck_opponent(direction)` emits → gameplay calls `Opponent.set_action(HIT_LOW, Direction.RIGHT)` (mirrored to face the card coming from screen-right), holds `HIT_HOLD_DURATION` (~250ms), then transitions to `GUARD_DOWN`. Carousel input (`menu_left` / `menu_right` / `menu_confirm`) is locked the moment K fires (`_is_punching` gate) and stays locked until the punch chain completes. Tofu's deck (image-only) skips the reaction typewriter — gameplay calls `RiddleBox.hide()` instead of `show_reaction()` — but the punch choreography still plays. On the WRONG path, Reaction State persists through the breather gap until the next prompt loads. On the NEUTRAL path, gameplay waits for the reaction typewriter to complete (via the `body_render_complete` signal), then holds `MatchPacing.NEUTRAL_READ_HOLD` seconds, then re-displays the SAME prompt instantly via `RiddleBox.display_instant()` — no typewriter, no read floor — and replays the Simon chain at its current length from step 0. On the RIGHT path, it persists into the Attack Phase show/repeat until the first registered W/A/S/D press, which hides the riddle for the rest of the phase; an attack timeout leaves the reaction visible through `_return_to_defense` until the next prompt loads.
```

- [ ] **Step 3: Update the "Riddle Encounter" section**

Find the line starting with `- **Riddle Encounter** —` (currently line 17). The body mentions the carousel is part of the riddle box. Replace the first sentence with:

```
A discrete window during Defense Phase in which the riddle box (bottom-center) and the **Answer Carousel** (upper-right play area) are visible and the player can cycle / submit an answer.
```

The rest of the bullet (navigation, confirm behavior, encounter-end events) stays unchanged.

- [ ] **Step 4: Split the "Riddle Box" UI Region into two regions**

Find the line starting with `- **Riddle Box** —` (currently line 69). Replace it AND the following `- **Answer Cards** —` bullet (currently line 70) with two new bullets:

```
- **Riddle Box** — Bottom-center of screen. Body-text-or-image only. Snaps in/out at encounter boundaries. No longer contains the answer cards — those live in the **Answer Carousel** above.
- **Answer Carousel** — Upper-right play area (rough anchor ~1280, 410 on the 1920×1080 stage), free-floating UI cluster of three `AnswerCard` instances arranged on a diagonal axis (L lower-left, M center, R upper-right). The selected answer is always the center card at full scale; the two unselected sit at `SIDE_SCALE` (0.7) on the diagonal, z-ordered behind so they overlap the center card by ~60px. J/L rotates the carousel along the diagonal (wrap-around — the side card displaced toward the rotation direction slides off the corresponding edge and re-enters from the opposite edge); K picks the center card and triggers the punch choreography. The carousel is hidden during the body typewriter and fades in once typing completes (no fade for image-body / NEUTRAL re-display paths). All card positions/scales/z route through a single transform seam in `answer_carousel.gd` (`_compute_card_transform(index, rotation_state)` + `_make_position(anchor)`) per ADR-0001.
```

- [ ] **Step 5: Update the "Riddle / Dialogue Prompt" section's last sentence about shuffling**

Find the line starting with `- **Riddle / Dialogue Prompt** —` (currently line 14). The current sentence says "each time `RiddleBox.display(prompt)` is called, the three answers are reshuffled..." Update it to:

```
each time `AnswerCarousel.display_prompt(prompt)` is called, the three answers are reshuffled before being assigned to the carousel's left / center / right rotational positions.
```

- [ ] **Step 6: Verify nothing else references "RiddleBox" owning the cards**

```bash
grep -n "RiddleBox" CONTEXT.md
```

Expected: only references to the body-text role (typewriter, `body_render_complete`, `is_rendering`, `display`, `display_instant`, `hide`, the `_picked_answers` legacy reference should not appear). If any sentence still says "RiddleBox … cards" or "RiddleBox owns the carousel" or similar, update it for the new architecture.

- [ ] **Step 7: Commit**

```bash
git add CONTEXT.md
git commit -m "$(cat <<'EOF'
docs(carousel): lock in CONTEXT for extracted carousel + punch chain

Updates CONTEXT.md to describe the new architecture before any code
changes: Answer Carousel is now a sibling UI region (not a child of
RiddleBox), the Reaction State runs a glove-punch choreography on
K-confirm with card flight into opponent body_hit_low → guard_down,
and the Riddle Box / Answer Cards UI regions are split apart.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Create `AnswerCarousel` scene + script (copy of carousel internals)

Create the new scene and script as a faithful copy of the carousel-related portions of `riddle_box.gd` + the `Answers` subtree of `riddle_box.tscn`. The new scene is not yet wired into `gameplay.tscn` (Task 4 does that), but it can be instantiated standalone for testing.

**Files:**
- Create: `scripts/ui/answer_carousel.gd`
- Create: `scenes/ui/answer_carousel.tscn`

- [ ] **Step 1: Create `scripts/ui/answer_carousel.gd`**

Write the new script with the full carousel logic copied from `riddle_box.gd`. Notable differences from the source: class name is `AnswerCarousel` (not `RiddleBox`), entry point is `display_prompt(prompt)` instead of being driven by `_setup_display(prompt)` inside `RiddleBox.display()`, the cards live under `Cards/Left|Middle|Right` instead of `Layout/Answers/Left|Middle|Right`, fade-in is exposed as `start_fade_in()` (public so RiddleBox's `body_render_complete` signal can trigger it via gameplay's wiring in Task 4), reaction state is mirrored locally via a `State` enum, `show_reaction_for(picked_index)` triggers the exit tween, and the `answer_submitted` signal now carries `(outcome: int, picked: DialogueAnswer)`:

```gdscript
class_name AnswerCarousel
extends Control

signal answer_submitted(outcome: int, picked: DialogueAnswer)

enum State { NORMAL, REACTION }

# Carousel layout — container-local (the AnswerCarousel root is the origin).
const CONTAINER_WIDTH := 900.0
const CONTAINER_HEIGHT := 197.0
const CARD_WIDTH := 288.0
const CARD_HEIGHT := 197.0
const CENTER_X := CONTAINER_WIDTH * 0.5
const CENTER_Y := CONTAINER_HEIGHT * 0.5
const SIDE_X_OFFSET := 200.0
const OFF_SCREEN_X_OFFSET := 600.0
const SIDE_SCALE := 0.7
const CENTER_SCALE := 1.0
const CENTER_Z := 10
const SIDE_Z := 0
# Animation timings (seconds).
const ROTATION_DURATION := 0.18
const FADE_IN_DURATION := 0.15
const EXIT_DURATION := 0.18

enum Slot { OFF_LEFT, SIDE_LEFT, CENTER, SIDE_RIGHT, OFF_RIGHT }

@onready var _cards: Array[AnswerCard] = [
	$Cards/Left,
	$Cards/Middle,
	$Cards/Right,
]

var _highlight_index: int = 1  # Card whose current role is Slot.CENTER.
var _state: int = State.NORMAL
var _picked_answers: Array[DialogueAnswer] = []
var _rotation_tween: Tween = null
var _is_rotating: bool = false
var _queued_rotation: int = 0
var _is_fading_in: bool = false
var _fade_tween: Tween = null
var _exit_tween: Tween = null

# Rotation state drives _compute_card_transform. When at rest,
# from_center == to_center and progress == 1.0. While a rotation tween is
# in flight, progress interpolates 0.0 → 1.0 from from_center to to_center.
var _rotation_state := {
	"from_center": 1,
	"to_center": 1,
	"progress": 1.0,
}

func _ready() -> void:
	# Pivot at card center so scale shrinks around the card's visual middle,
	# not its top-left. Set once; position formula in _compute_card_transform
	# assumes pivot is at the card's geometric center.
	for card in _cards:
		card.pivot_offset = Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)

func get_state() -> int:
	return _state

func get_cards() -> Array:
	return _cards

# Stages the cards for a new prompt. Sets initial alpha based on prompt type:
# text-body prompts start at alpha 0 (will fade in once the body typewriter
# completes — gameplay wires that), image-body prompts start at alpha 1.
func display_prompt(prompt: DialoguePrompt) -> void:
	_state = State.NORMAL
	visible = true
	for card in _cards:
		card.visible = true
	var start_alpha: float = 0.0 if not prompt.has_image_body() else 1.0
	for card in _cards:
		card.modulate.a = start_alpha
	_is_fading_in = false
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	if _exit_tween:
		_exit_tween.kill()
		_exit_tween = null
	# Answer cards are shuffled per display so position never reveals outcome.
	# Don't mutate prompt.answers — the deck reuses prompts across redraws.
	var shuffled := prompt.answers.duplicate()
	shuffled.shuffle()
	_picked_answers.clear()
	for i in _cards.size():
		if i < shuffled.size():
			_cards[i].display(shuffled[i])
			_picked_answers.append(shuffled[i])
	_highlight_index = 1
	_rotation_state.from_center = 1
	_rotation_state.to_center = 1
	_rotation_state.progress = 1.0
	_is_rotating = false
	_queued_rotation = 0
	if _rotation_tween:
		_rotation_tween.kill()
		_rotation_tween = null
	_apply_all_transforms()

# Synchronous variant — used by the NEUTRAL re-display path. Skips the fade
# regardless of prompt type (player has already read the prompt once).
func display_prompt_instant(prompt: DialoguePrompt) -> void:
	display_prompt(prompt)
	for card in _cards:
		card.modulate.a = 1.0

# Awaitable. Public so the caller (gameplay) can trigger the fade once
# RiddleBox.body_render_complete fires. Image-body prompts skip this.
func start_fade_in() -> void:
	_is_fading_in = true
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for card in _cards:
		_fade_tween.tween_property(card, "modulate:a", 1.0, FADE_IN_DURATION)
	await _fade_tween.finished
	_is_fading_in = false

# Called by gameplay AFTER answer_submitted is handled. Triggers the side-card
# exit tween + flips local state to REACTION (locks input). The picked card
# stays put (Phase 3 makes it fly).
func show_reaction_for(picked_index: int) -> void:
	if picked_index < 0 or picked_index >= _cards.size():
		return
	_state = State.REACTION
	_start_exit_tween(picked_index)

func _start_exit_tween(picked_index: int) -> void:
	# kill() suppresses the old tween's finished signal — the prior lambda
	# (which closed over a possibly-different picked_index) will not fire.
	if _exit_tween:
		_exit_tween.kill()
		_exit_tween = null
	_exit_tween = create_tween()
	_exit_tween.set_parallel(true)
	for i in _cards.size():
		if i == picked_index:
			continue
		var card := _cards[i]
		# Target position: the off-screen anchor on the card's CURRENT side.
		# The picked card is at CENTER (its slot role is computed relative to
		# picked_index), so the unpicked cards are guaranteed SIDE_LEFT/SIDE_RIGHT.
		var role := _slot_role_for(i, picked_index)
		var target_anchor_x: float
		if role == Slot.SIDE_LEFT:
			target_anchor_x = _slot_anchor_x(Slot.OFF_LEFT)
		else:
			target_anchor_x = _slot_anchor_x(Slot.OFF_RIGHT)
		var target_position := _make_position(target_anchor_x)
		_exit_tween.tween_property(card, "position", target_position, EXIT_DURATION)
		_exit_tween.tween_property(card, "modulate:a", 0.0, EXIT_DURATION)
	_exit_tween.finished.connect(func():
		for i in _cards.size():
			if i != picked_index:
				_cards[i].visible = false
	)

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# Lock all carousel input while the cards are still arriving (fade-in in
	# flight). The body typewriter gate (_is_rendering on RiddleBox) is
	# enforced by gameplay not calling start_fade_in() until the typewriter
	# finishes — there's no carousel-local typewriter state anymore.
	if _is_fading_in:
		return
	# J/L cycle with wrap; I is intentionally unused (per CONTEXT.md Riddle
	# Encounter). Confirm carries no SFX — the riddle outcome SFX
	# (riddle_correct/_neutral/_wrong) is the feedback for picking an answer.
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		var picked := _picked_answers[picked_index]
		_state = State.REACTION  # lock for the duration; gameplay calls show_reaction_for next
		answer_submitted.emit(picked.outcome, picked)

func _cycle_highlight(delta: int) -> void:
	if _is_rotating:
		if _queued_rotation != 0:
			# Queue is already full (depth 1). Drop this press silently.
			return
		# Queue depth 1: buffer this press for when the in-flight tween ends.
		# Audio fires at input time so queued double-taps are audibly confirmed.
		AudioBus.play_sfx("menu_change_item")
		_highlight_index = (_highlight_index + delta + _cards.size()) % _cards.size()
		_queued_rotation = delta
		return
	# Not rotating: advance index, fire audio, and start the tween immediately.
	AudioBus.play_sfx("menu_change_item")
	_highlight_index = (_highlight_index + delta + _cards.size()) % _cards.size()
	_start_rotation_to(_highlight_index)

func _start_rotation_to(target_center: int) -> void:
	_is_rotating = true
	_rotation_state.from_center = _rotation_state.to_center
	_rotation_state.to_center = target_center
	_rotation_state.progress = 0.0
	if _rotation_tween:
		_rotation_tween.kill()
		_rotation_tween = null
	_rotation_tween = create_tween()
	_rotation_tween.tween_method(_apply_rotation_progress, 0.0, 1.0, ROTATION_DURATION)
	_rotation_tween.finished.connect(_on_rotation_finished)

func _apply_rotation_progress(p: float) -> void:
	_rotation_state.progress = p
	_apply_all_transforms()

func _on_rotation_finished() -> void:
	_is_rotating = false
	_rotation_state.from_center = _rotation_state.to_center
	_rotation_state.progress = 1.0
	if _queued_rotation != 0:
		_queued_rotation = 0
		# _highlight_index and the menu_change_item SFX were both committed at
		# queue time in _cycle_highlight — just drive the visual to the target.
		_start_rotation_to(_highlight_index)

func _apply_all_transforms() -> void:
	for i in _cards.size():
		var t := _compute_card_transform(i, _rotation_state)
		_cards[i].position = t.position
		_cards[i].scale = t.scale
		_cards[i].z_index = t.z

# THE SEAM. All carousel position/scale/z computation MUST route through this
# function — no inline transform math anywhere else. ADR-0001 records the
# rationale: Phase C's 3D-orbit upgrade replaces this function body wholesale.
#
# state is a Dictionary with keys: from_center (int), to_center (int),
# progress (float 0..1). At-rest states have from_center == to_center.
func _compute_card_transform(card_index: int, state: Dictionary) -> Dictionary:
	var from_role := _slot_role_for(card_index, int(state.from_center))
	var to_role := _slot_role_for(card_index, int(state.to_center))
	var progress: float = state.progress

	# Wrap = card swaps sides without passing through center. Its visual path
	# is a two-segment teleport through the off-screen position on its
	# leaving side. Non-wrapping cards lerp directly between adjacent slots.
	var wraps := (from_role == Slot.SIDE_LEFT and to_role == Slot.SIDE_RIGHT) \
		or (from_role == Slot.SIDE_RIGHT and to_role == Slot.SIDE_LEFT)

	var anchor_x: float
	if wraps:
		if from_role == Slot.SIDE_LEFT:
			if progress < 0.5:
				anchor_x = lerp(_slot_anchor_x(Slot.SIDE_LEFT), _slot_anchor_x(Slot.OFF_LEFT), progress * 2.0)
			else:
				anchor_x = lerp(_slot_anchor_x(Slot.OFF_RIGHT), _slot_anchor_x(Slot.SIDE_RIGHT), (progress - 0.5) * 2.0)
		else:
			if progress < 0.5:
				anchor_x = lerp(_slot_anchor_x(Slot.SIDE_RIGHT), _slot_anchor_x(Slot.OFF_RIGHT), progress * 2.0)
			else:
				anchor_x = lerp(_slot_anchor_x(Slot.OFF_LEFT), _slot_anchor_x(Slot.SIDE_LEFT), (progress - 0.5) * 2.0)
	else:
		anchor_x = lerp(_slot_anchor_x(from_role), _slot_anchor_x(to_role), progress)

	# Scale lerps from raw progress, not the piecewise-remapped anchor_x above.
	# For wrap cards both from_role and to_role are SIDE slots (same scale), so
	# this stays flat — correct. If easing is ever added to progress, revisit.
	var scale_val: float = lerp(_slot_scale(from_role), _slot_scale(to_role), progress)
	var z_val := _slot_z(to_role)

	return {
		"position": _make_position(anchor_x),
		"scale": Vector2(scale_val, scale_val),
		"z": z_val,
	}

# Converts a slot anchor-X into the card's top-left position. Pivot is at the
# card's geometric center (set in _ready), so this lands the visual center on
# (anchor_x, CENTER_Y). All position math MUST route through this — ADR-0001.
func _make_position(anchor_x: float) -> Vector2:
	return Vector2(anchor_x - CARD_WIDTH / 2.0, CENTER_Y - CARD_HEIGHT / 2.0)

func _slot_role_for(card_index: int, center_index: int) -> int:
	var relative := (card_index - center_index + 3) % 3
	match relative:
		0: return Slot.CENTER
		1: return Slot.SIDE_RIGHT
		_: return Slot.SIDE_LEFT  # relative == 2

func _slot_anchor_x(slot: int) -> float:
	match slot:
		Slot.OFF_LEFT: return CENTER_X - OFF_SCREEN_X_OFFSET
		Slot.SIDE_LEFT: return CENTER_X - SIDE_X_OFFSET
		Slot.CENTER: return CENTER_X
		Slot.SIDE_RIGHT: return CENTER_X + SIDE_X_OFFSET
		Slot.OFF_RIGHT: return CENTER_X + OFF_SCREEN_X_OFFSET
		_: return CENTER_X

func _slot_scale(slot: int) -> float:
	if slot == Slot.CENTER:
		return CENTER_SCALE
	return SIDE_SCALE

func _slot_z(slot: int) -> int:
	if slot == Slot.CENTER:
		return CENTER_Z
	return SIDE_Z
```

- [ ] **Step 2: Create `scenes/ui/answer_carousel.tscn`**

```
[gd_scene load_steps=3 format=3 uid="uid://b1answercarousel001"]

[ext_resource type="Script" path="res://scripts/ui/answer_carousel.gd" id="1_carousel"]
[ext_resource type="PackedScene" path="res://scenes/ui/answer_card.tscn" id="2_answer"]

[node name="AnswerCarousel" type="Control"]
custom_minimum_size = Vector2(900, 197)
layout_mode = 3
anchors_preset = 0
offset_right = 900.0
offset_bottom = 197.0
script = ExtResource("1_carousel")

[node name="Cards" type="Control" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2

[node name="Left" parent="Cards" instance=ExtResource("2_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0

[node name="Middle" parent="Cards" instance=ExtResource("2_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0

[node name="Right" parent="Cards" instance=ExtResource("2_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0
```

- [ ] **Step 3: Verify the new scene parses cleanly**

```bash
godot --headless --path . --check-only res://scenes/ui/answer_carousel.tscn
```

Expected: exit code 0, no errors. If `--check-only` isn't recognized in this Godot version, run an editor import pass instead:

```bash
godot --headless --path . --import 2>&1 | grep -i "error\|carousel"
```

Expected: no errors mentioning `answer_carousel.tscn` or `answer_carousel.gd`.

- [ ] **Step 4: Commit**

```bash
git add scripts/ui/answer_carousel.gd scenes/ui/answer_carousel.tscn
git commit -m "$(cat <<'EOF'
feat(carousel): extract AnswerCarousel scene + script from RiddleBox

Carbon-copy of the carousel internals from riddle_box.gd into a new
standalone scene+script. RiddleBox is not yet slimmed (Task 4 does
that); this commit just stands up the new files so Task 3 can write
the carousel-only tests against them. answer_submitted now carries
(outcome, picked_answer) so the caller (gameplay) can route reaction
text + outcome handling without RiddleBox reaching into _picked_answers.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Port carousel tests to `test_answer_carousel.gd`

Copy all 13 tests from `test_riddle_box_carousel.gd` (still on disk; deleted in Task 4) into a new `test_answer_carousel.gd`, rewriting them to mount `AnswerCarousel` instead of `RiddleBox`. Drop assertions that don't apply (e.g., `is_rendering` and fade-in tests that depended on RiddleBox's typewriter — those are restored in Task 4 once the carousel is wired to receive the fade signal from gameplay).

**Files:**
- Create: `tests/unit/test_answer_carousel.gd`

- [ ] **Step 1: Write the test file**

```gdscript
extends GutTest

const AnswerCarouselScene := preload("res://scenes/ui/answer_carousel.tscn")

# Builds a prompt with three text answers and the given reaction strings.
# reactions: 3-element Array of String; pass "" for empty reaction (Tofu shape).
func _make_prompt(reactions: Array) -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = "body"
	var outcomes := [Outcome.Type.WRONG, Outcome.Type.NEUTRAL, Outcome.Type.RIGHT]
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcomes[i]
		a.reaction_text = reactions[i]
		p.answers.append(a)
	return p

func _mount() -> AnswerCarousel:
	var c: AnswerCarousel = AnswerCarouselScene.instantiate()
	add_child_autoqfree(c)
	return c

func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

# --- Phase A: cycle input mapping ---

func test_j_decrements_highlight_with_wrap():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(c._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "one J should land on index 0")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 2, "second J should wrap to index 2")

func test_l_increments_highlight_with_wrap():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(c._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 2, "one L should land on index 2")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "second L should wrap to index 0")

func test_i_is_noop_in_carousel():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0)
	_send_action("menu_up")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "menu_up must not change the highlight inside AnswerCarousel")

# --- At-rest layout ---

func test_display_lays_out_cards_with_center_at_full_scale_sides_shrunk():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	assert_almost_eq(cards[1].scale.x, 1.0, 0.001, "default center card should be at full scale")
	assert_almost_eq(cards[1].scale.y, 1.0, 0.001)
	assert_almost_eq(cards[0].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "left side card should be at SIDE_SCALE")
	assert_almost_eq(cards[2].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "right side card should be at SIDE_SCALE")

func test_cycle_swaps_which_card_is_at_full_scale():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_almost_eq(c.get_cards()[1].scale.x, 1.0, 0.001)
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION + 0.05).timeout
	assert_almost_eq(c.get_cards()[2].scale.x, 1.0, 0.001, "after L, card 2 should be at center")
	assert_almost_eq(c.get_cards()[1].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "after L, card 1 should be at SIDE_SCALE")

# --- Rotation + queue + K-lock ---

func test_two_rapid_l_presses_land_on_target_via_queue():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION * 2.5).timeout
	assert_eq(c._highlight_index, 0, "two queued L presses should land on index 0 (wrap)")

func test_third_input_during_rotation_is_dropped_not_stacked():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	_send_action("menu_right")
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION * 2.5).timeout
	assert_eq(c._highlight_index, 0, "third press should be dropped — final index is 0, not 1")

func test_confirm_during_rotation_is_rejected():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append([outcome, picked]))
	_send_action("menu_right")
	await get_tree().process_frame  # tween started
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "K during rotation must not emit answer_submitted")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION + 0.05).timeout
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 1, "K after rotation completes should emit answer_submitted")

# --- Fade-in visibility ---

func test_display_prompt_text_body_starts_cards_transparent():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 0.0, 0.01, "text-body prompt should stage cards at alpha 0")

func test_display_prompt_image_body_starts_cards_opaque():
	var c := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	prompt.body_image = PlaceholderTexture2D.new()
	# DialoguePrompt.has_image_body() returns true when body_image is set.
	c.display_prompt(prompt)
	await get_tree().process_frame
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "image-body prompt should stage cards at alpha 1")

func test_start_fade_in_resolves_after_fade_duration():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var t_start := Time.get_ticks_msec()
	await c.start_fade_in()
	var elapsed_ms := Time.get_ticks_msec() - t_start
	var expected_ms := int(AnswerCarousel.FADE_IN_DURATION * 1000.0)
	assert_true(elapsed_ms >= expected_ms - 30, "start_fade_in should await full FADE_IN_DURATION — expected ≥%dms, got %dms" % [expected_ms - 30, elapsed_ms])
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "cards should be opaque after fade-in")

func test_display_prompt_instant_skips_fade_cards_immediately_visible():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "display_prompt_instant should show cards at full opacity immediately")

func test_jl_locked_while_fading_in():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	c.start_fade_in()  # don't await — fade in flight
	await get_tree().create_timer(AnswerCarousel.FADE_IN_DURATION * 0.4).timeout
	# Fade is in flight; any alpha in (0, 1) satisfies the check.
	assert_almost_eq(c.get_cards()[1].modulate.a, 0.5, 0.5, "still fading in (alpha somewhere in 0..1)")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 1, "J/L must be ignored during fade-in")

# --- Confirm + exit tween ---

func test_confirm_emits_answer_submitted_with_outcome_and_picked():
	var c := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	c.display_prompt_instant(prompt)
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append([outcome, picked]))
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 1, "K should emit answer_submitted once")
	var event: Array = emitted[0]
	assert_true(event[1] is DialogueAnswer, "second arg should be the picked DialogueAnswer")
	# After shuffle, the middle card is one of the three answers; outcome matches.
	var picked_outcome: int = event[0]
	var picked: DialogueAnswer = event[1]
	assert_eq(picked_outcome, picked.outcome, "outcome arg should match picked.outcome")

func test_show_reaction_for_animates_unpicked_cards_out():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	var start_pos_0: Vector2 = cards[0].position
	var start_pos_2: Vector2 = cards[2].position
	c.show_reaction_for(1)
	await get_tree().create_timer(AnswerCarousel.EXIT_DURATION * 0.5).timeout
	assert_true(cards[0].modulate.a < 0.9, "left card alpha should be tweening down")
	assert_true(cards[2].modulate.a < 0.9, "right card alpha should be tweening down")
	assert_true(cards[0].position != start_pos_0, "left card position should be tweening toward off-screen")
	assert_true(cards[2].position != start_pos_2, "right card position should be tweening toward off-screen")

func test_show_reaction_for_locks_input():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	c.show_reaction_for(1)
	await get_tree().process_frame
	assert_eq(c.get_state(), AnswerCarousel.State.REACTION)
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 1, "J/L must be ignored in REACTION state")
```

- [ ] **Step 2: Run the new test file and confirm all pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: 15/15 passed. If any test references a method that doesn't exist on AnswerCarousel (e.g., `display_prompt`, `display_prompt_instant`, `start_fade_in`, `show_reaction_for`, `get_cards`, `get_state`), that's a typo in Task 2 — fix it before this task completes.

- [ ] **Step 3: Run the existing `test_riddle_box.gd` and `test_riddle_box_carousel.gd` to confirm no regressions**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: 9/9 and 13/13. AnswerCarousel hasn't been wired into anything yet — the existing RiddleBox-owned carousel still works.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test_answer_carousel.gd
git commit -m "$(cat <<'EOF'
test(carousel): port carousel tests to test_answer_carousel.gd

15 tests covering the extracted AnswerCarousel: cycle input mapping
(3), at-rest layout (2), rotation tween + queue + K-lock (3), fade-in
visibility (5), confirm signal + exit tween (2). The existing
test_riddle_box_carousel.gd is unchanged for now — Task 4 deletes it
once gameplay is rewired to the new carousel.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Wire AnswerCarousel into gameplay, slim RiddleBox

The atomic refactor: gameplay now uses AnswerCarousel as the input/signal owner, RiddleBox shrinks to body-only, the old `Layout/Answers` is removed from `riddle_box.tscn`, the old `test_riddle_box_carousel.gd` is deleted, and `test_riddle_box.gd` drops the now-obsolete carousel-coupled assertions. After this commit, gameplay looks visually identical to today but the responsibilities are split.

**Files:**
- Modify: `scenes/gameplay.tscn` (add `AnswerCarousel` instance at the OLD position so layout doesn't shift)
- Modify: `scripts/gameplay.gd` (re-wire `answer_submitted` signal + fade-in trigger)
- Modify: `scripts/ui/riddle_box.gd` (delete carousel internals; `show_reaction` signature changes)
- Modify: `scenes/ui/riddle_box.tscn` (delete `Layout/Answers` subtree)
- Modify: `tests/unit/test_riddle_box.gd` (drop carousel-related tests; update `show_reaction` test)
- Delete: `tests/unit/test_riddle_box_carousel.gd` + `tests/unit/test_riddle_box_carousel.gd.uid`

- [ ] **Step 1: Slim `scripts/ui/riddle_box.gd` to body-only**

Replace the ENTIRE file with:

```gdscript
class_name RiddleBox
extends Control

# Emitted when a typewriter pass (body OR reaction) finishes naturally.
# Not emitted on early-bail (superseded by a new display/show_reaction) or
# on display_instant. Used by gameplay's Riddle Render Gate to await a
# reaction typewriter from outside RiddleBox, and by AnswerCarousel's
# fade-in trigger (gameplay forwards body_render_complete to start_fade_in).
signal body_render_complete

enum State { NORMAL, REACTION }

@onready var _body_text: RichTextLabel = $Layout/Body/Text
@onready var _body_image: TextureRect = $Layout/Body/Image

var _typewriter_speed: float = 60.0
var _typewriter_generation: int = 0
var _is_rendering: bool = false
var _state: int = State.NORMAL

func get_state() -> int:
	return _state

func is_rendering() -> bool:
	return _is_rendering

# Awaitable. Resolves when the body typewriter completes (or immediately for
# image-body prompts). Caller is the gate that controls when DefensePhase
# activates AND when the AnswerCarousel fades in — see Riddle Render Gate
# in CONTEXT.md.
func display(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	if prompt.has_image_body():
		return
	await _start_typewriter(prompt.body_text)

# Synchronous full-text display. Used by the NEUTRAL re-display path where
# the player has already read this prompt — typewriter would be busywork.
func display_instant(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	if prompt.has_image_body():
		return
	_typewriter_generation += 1  # cancel any in-flight typewriter
	_is_rendering = false
	_body_text.text = "[center]%s[/center]" % prompt.body_text
	_body_text.visible_characters = -1

func _setup_display(prompt: DialoguePrompt) -> void:
	_state = State.NORMAL
	visible = true
	if prompt.has_image_body():
		_body_image.texture = prompt.body_image
		_body_image.visible = true
		_body_text.visible = false
	else:
		_body_text.visible = true
		_body_image.visible = false

# Awaitable. Resolves when the reaction typewriter completes. Caller has
# already pre-checked has_reaction() — for empty-reaction prompts (Tofu),
# the caller invokes hide() directly instead of show_reaction().
func show_reaction(reaction_text: String) -> void:
	_body_image.visible = false
	_body_text.visible = true
	_state = State.REACTION
	await _start_typewriter(reaction_text)

func _start_typewriter(text: String) -> void:
	_typewriter_generation += 1
	var my_generation := _typewriter_generation
	_is_rendering = true
	# Wrap in [center] so each line auto-centers horizontally.
	# visible_characters counts displayed glyphs (BBCode tags excluded), so
	# use get_total_character_count() instead of source-string length —
	# otherwise the loop would over-shoot the cap and spin forever.
	_body_text.text = "[center]%s[/center]" % text
	_body_text.visible_characters = 0
	var total := _body_text.get_total_character_count()
	while _body_text.visible_characters < total:
		if my_generation != _typewriter_generation:
			return
		_body_text.visible_characters += 1
		await get_tree().create_timer(1.0 / _typewriter_speed).timeout
	if my_generation == _typewriter_generation:
		_is_rendering = false
		body_render_complete.emit()
```

Note the public API changes from PR #14:
- `answer_submitted` signal — REMOVED (moved to AnswerCarousel)
- `show_reaction(picked_index)` — now `show_reaction(reaction_text: String)`; caller pre-checks `has_reaction()`
- `get_cards()` — REMOVED
- All carousel state vars, slot helpers, transform seam, tweens — REMOVED

- [ ] **Step 2: Slim `scenes/ui/riddle_box.tscn`**

Find the `Answers` subtree (the `[node name="Answers" type="Control" parent="Layout"]` block and its three child instances `Left` / `Middle` / `Right`). Delete the entire subtree — both the parent and the three child blocks.

Also remove the `ext_resource` reference to `answer_card.tscn` at the top of the file (the line `[ext_resource type="PackedScene" path="res://scenes/ui/answer_card.tscn" id="3_answer"]`) since nothing in this scene references it anymore. Renumber the `load_steps` count in the gd_scene header to match the new resource count.

After the edit, the file should contain only the `RiddleBox` root, the `Layout` VBox, and the `Body` TextureRect with its `Text` + `Image` children.

- [ ] **Step 3: Add `AnswerCarousel` instance to `scenes/gameplay.tscn` at the OLD position**

Find the existing `[node name="RiddleBox" parent="." instance=ExtResource("6_riddle")]` block in `scenes/gameplay.tscn`. The RiddleBox sits at `offset_left = -450, offset_top = -542, offset_right = 450, offset_bottom = -40` (centered, 900×502, bottom-anchored).

Add a new `ext_resource` reference at the top of the file for the carousel scene:

```
[ext_resource type="PackedScene" path="res://scenes/ui/answer_carousel.tscn" id="10_carousel"]
```

(Use the next available numeric ID — check the file for the highest existing `id="N_..."` and pick `N+1`. The string above shows id `10_carousel` as a placeholder; adjust to match.)

Add the carousel node block AFTER the RiddleBox block. The carousel container is 900×197 (carousel-local). To place it where the old answers row was rendering today (top of the riddle box, which is the top of a 900×502 box anchored bottom-center), the carousel's screen position needs to match the OLD position of the `Layout/Answers` Control. That was inside the riddle box VBox at the top, so its global screen position is approximately the top of the riddle box. The riddle box's top-left is at `(960 - 450, 1080 - 542 - 40)` = `(510, 498)`.

Insert this block at the end of the scene file:

```
[node name="AnswerCarousel" parent="." instance=ExtResource("10_carousel")]
offset_left = 510.0
offset_top = 498.0
offset_right = 1410.0
offset_bottom = 695.0
```

(`offset_right = offset_left + 900`; `offset_bottom = offset_top + 197`.)

These coordinates place the carousel container exactly where the old answers row was in the riddle box, so visually nothing changes after this task.

- [ ] **Step 4: Re-wire `scripts/gameplay.gd`**

Open `scripts/gameplay.gd`. Find the existing `@onready var _riddle: RiddleBox = $RiddleBox` (line 11) and add a sibling line right after:

```gdscript
@onready var _carousel: AnswerCarousel = $AnswerCarousel
```

Find the existing `_riddle.answer_submitted.connect(_on_answer_submitted)` line (around line 103). Replace it with:

```gdscript
	_carousel.answer_submitted.connect(_on_answer_submitted)
	# Forward the body-render-complete signal to the carousel's fade-in.
	_riddle.body_render_complete.connect(_carousel.start_fade_in)
```

Find the existing `_on_answer_submitted(outcome: int)` function (around line 549). Change its signature and add the reaction routing:

```gdscript
func _on_answer_submitted(outcome: int, picked: DialogueAnswer) -> void:
	# Route reaction text or hide based on whether the picked answer has one.
	# Empty-reaction (Tofu) path hides the riddle box body; AnswerCarousel
	# handles its own card visibility via show_reaction_for() below.
	if picked.has_reaction():
		_riddle.show_reaction(picked.reaction_text)
	else:
		_riddle.hide()
	# Tell the carousel to start its exit tween + lock input.
	# Use _highlight_index because AnswerCarousel may have already advanced
	# _highlight_index from a queued rotation; we want the actual picked card.
	_carousel.show_reaction_for(_carousel._highlight_index)
```

Wait — `_carousel._highlight_index` is private. We need to capture the picked card index BEFORE the carousel emits, or have the carousel emit it. Simpler: AnswerCarousel already locks input on emit (sets `_state = REACTION`), so the exit tween can be triggered internally. Update Task 4 step 4 to drop the external `show_reaction_for` call and modify AnswerCarousel to call `_start_exit_tween(_highlight_index)` itself in `_unhandled_input`.

Cancel the previous instruction; instead apply this to `scripts/gameplay.gd`:

```gdscript
func _on_answer_submitted(outcome: int, picked: DialogueAnswer) -> void:
	# Route reaction text or hide based on whether the picked answer has one.
	# Empty-reaction (Tofu) path hides the riddle box body; AnswerCarousel
	# already started its exit tween and locked input in _unhandled_input.
	if picked.has_reaction():
		_riddle.show_reaction(picked.reaction_text)
	else:
		_riddle.hide()
```

(The original `_on_answer_submitted(outcome: int)` body had other logic — keep all of it, just add the show_reaction/hide routing at the top.)

Then in `scripts/ui/answer_carousel.gd`, update `_unhandled_input`'s confirm branch from this:

```gdscript
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		var picked := _picked_answers[picked_index]
		_state = State.REACTION  # lock for the duration; gameplay calls show_reaction_for next
		answer_submitted.emit(picked.outcome, picked)
```

To this:

```gdscript
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		var picked := _picked_answers[picked_index]
		_state = State.REACTION  # lock for the duration
		_start_exit_tween(picked_index)
		answer_submitted.emit(picked.outcome, picked)
```

Now the carousel handles its own exit tween at confirm time — gameplay never needs to call `show_reaction_for`. `show_reaction_for` stays in the public API for tests but isn't used by gameplay.

- [ ] **Step 5: Slim `tests/unit/test_riddle_box.gd`**

Open `tests/unit/test_riddle_box.gd`. The current tests assume RiddleBox owns cards, the answer_submitted signal, etc. Replace the entire file with:

```gdscript
extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

func _make_prompt() -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = "body"
	var outcomes := [Outcome.Type.WRONG, Outcome.Type.NEUTRAL, Outcome.Type.RIGHT]
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcomes[i]
		a.reaction_text = "r%d" % i
		p.answers.append(a)
	return p

func _mount() -> RiddleBox:
	var box: RiddleBox = RiddleBoxScene.instantiate()
	add_child_autoqfree(box)
	return box

func test_display_enters_normal_state():
	var box := _mount()
	await box.display(_make_prompt())
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)

func test_show_reaction_transitions_to_reaction_state():
	var box := _mount()
	await box.display(_make_prompt())
	box.show_reaction("a reaction")
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.REACTION)

func test_display_is_awaitable_and_resolves_after_typewriter():
	var box := _mount()
	# body="body" → 4 chars at default 60 cps ≈ 67ms typewriter (no fade —
	# that lives in AnswerCarousel now).
	var t_start := Time.get_ticks_msec()
	await box.display(_make_prompt())
	var elapsed_ms := Time.get_ticks_msec() - t_start
	assert_false(box.is_rendering(), "is_rendering should be false after display() resolves")
	assert_true(elapsed_ms >= 30, "display() should await typewriter — expected ≥30ms, got %dms" % elapsed_ms)

func test_body_render_complete_signal_fires_after_typewriter():
	var box := _mount()
	var fired := [false]
	box.body_render_complete.connect(func(): fired[0] = true)
	box.display(_make_prompt())
	await get_tree().create_timer(0.3).timeout
	assert_true(fired[0], "body_render_complete should emit when typewriter finishes naturally")

func test_display_instant_shows_full_text_synchronously():
	var box := _mount()
	box.display_instant(_make_prompt())
	assert_false(box.is_rendering(), "display_instant should not start typewriter")
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)

func test_show_reaction_starts_reaction_typewriter():
	var box := _mount()
	await box.display(_make_prompt())
	# show_reaction is awaitable — resolves after the reaction typewriter completes.
	var t_start := Time.get_ticks_msec()
	await box.show_reaction("hello")
	var elapsed_ms := Time.get_ticks_msec() - t_start
	# "hello" = 5 chars at 60 cps ≈ 83ms.
	assert_true(elapsed_ms >= 30, "show_reaction should await typewriter — expected ≥30ms, got %dms" % elapsed_ms)
	assert_false(box.is_rendering(), "is_rendering should be false after show_reaction resolves")
```

Six tests covering RiddleBox's slimmed contract — state transitions, typewriter timing, `body_render_complete` signal, `display_instant` synchronous behavior, `show_reaction` awaitable contract.

- [ ] **Step 6: Delete the old carousel test file**

```bash
git rm tests/unit/test_riddle_box_carousel.gd
rm -f tests/unit/test_riddle_box_carousel.gd.uid
```

The `.uid` file may or may not exist depending on whether Godot has imported the test yet. `rm -f` is safe either way.

- [ ] **Step 7: Run the full test suite**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: 6/6 baseline RiddleBox + 15/15 AnswerCarousel.

Also run the broader suite to confirm no other tests broke:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: all tests pass except any pre-existing unrelated failures (e.g., `test_difficulty_config.gd` may have a pre-existing issue noted in prior session — leave alone).

- [ ] **Step 8: Manual playtest**

SKIP — you are headless. The user will playtest at the end of Phase 5.

- [ ] **Step 9: Commit**

```bash
git add scripts/ui/riddle_box.gd scripts/ui/answer_carousel.gd scenes/ui/riddle_box.tscn scenes/gameplay.tscn scripts/gameplay.gd tests/unit/test_riddle_box.gd
git rm tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
refactor(carousel): wire AnswerCarousel sibling, slim RiddleBox

RiddleBox shrinks from ~411 lines to ~80: body text + typewriter +
body_render_complete signal + show_reaction(reaction_text) + hide().
All carousel internals (cards, slot helpers, transform seam, tweens,
input, state) moved to AnswerCarousel last task; this task wires
AnswerCarousel as a sibling of RiddleBox in gameplay.tscn at the
old answers-row screen position so layout is visually unchanged.

answer_submitted is now (outcome, picked_answer); gameplay's handler
routes picked.reaction_text into RiddleBox.show_reaction() or
RiddleBox.hide() for Tofu's empty-reaction case. The carousel's
own _unhandled_input fires _start_exit_tween() before emitting so
the side-card exit + reaction text run concurrently.

The render gate signal is forwarded: RiddleBox.body_render_complete
connects to AnswerCarousel.start_fade_in.

test_riddle_box.gd slims to 6 tests covering the new contract.
test_riddle_box_carousel.gd is deleted (replaced by
test_answer_carousel.gd last task).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Convert slot anchors to `Vector2` (linear, Y=0)

Refactor the transform seam to use Vector2 anchors throughout. This task is a pure refactor — the visual behavior is unchanged because `SIDE_OFFSET.y = 0` and `OFF_SCREEN_OFFSET.y = 0` (the new constants stay degenerate in this task). Task 6 sets the Y values to produce the diagonal tilt.

**Files:**
- Modify: `scripts/ui/answer_carousel.gd`
- Modify: `tests/unit/test_answer_carousel.gd` (adjust 2 tests for the new `Vector2` API)

- [ ] **Step 1: Replace the layout constant block in `answer_carousel.gd`**

Find the carousel layout constants block (currently lines ~10-26 of `answer_carousel.gd`). Replace it with:

```gdscript
# Carousel layout — container-local (the AnswerCarousel root is the origin).
# Slot anchors are Vector2 offsets from the container's logical CENTER point.
# Phase 6 sets SIDE_OFFSET.y / OFF_SCREEN_OFFSET.y to non-zero values for the
# diagonal tilt; this task leaves them at 0 so layout is unchanged.
const CONTAINER_WIDTH := 900.0
const CONTAINER_HEIGHT := 197.0
const CARD_WIDTH := 288.0
const CARD_HEIGHT := 197.0
const CENTER_X := CONTAINER_WIDTH * 0.5
const CENTER_Y := CONTAINER_HEIGHT * 0.5
const SIDE_OFFSET := Vector2(200.0, 0.0)        # X = distance to side slot, Y = vertical tilt
const OFF_SCREEN_OFFSET := Vector2(600.0, 0.0)  # X = distance to wrap exit, Y = vertical tilt
const SIDE_SCALE := 0.7
const CENTER_SCALE := 1.0
const CENTER_Z := 10
const SIDE_Z := 0
# Animation timings (seconds).
const ROTATION_DURATION := 0.18
const FADE_IN_DURATION := 0.15
const EXIT_DURATION := 0.18
```

- [ ] **Step 2: Replace `_slot_anchor_x(slot) -> float` with `_slot_anchor(slot) -> Vector2`**

Find the `_slot_anchor_x` function (currently lines ~285-292). Replace it with:

```gdscript
func _slot_anchor(slot: int) -> Vector2:
	match slot:
		Slot.OFF_LEFT:   return Vector2(CENTER_X - OFF_SCREEN_OFFSET.x,  CENTER_Y + OFF_SCREEN_OFFSET.y)
		Slot.SIDE_LEFT:  return Vector2(CENTER_X - SIDE_OFFSET.x,        CENTER_Y + SIDE_OFFSET.y)
		Slot.CENTER:     return Vector2(CENTER_X,                         CENTER_Y)
		Slot.SIDE_RIGHT: return Vector2(CENTER_X + SIDE_OFFSET.x,        CENTER_Y - SIDE_OFFSET.y)
		Slot.OFF_RIGHT:  return Vector2(CENTER_X + OFF_SCREEN_OFFSET.x,  CENTER_Y - OFF_SCREEN_OFFSET.y)
		_:               return Vector2(CENTER_X,                         CENTER_Y)
```

(Note the asymmetric Y sign: SIDE_LEFT / OFF_LEFT use `+SIDE_OFFSET.y` — they sit BELOW the center horizontal line. SIDE_RIGHT / OFF_RIGHT use `-SIDE_OFFSET.y` — they sit ABOVE. This is the L-lower-R-higher diagonal. With `SIDE_OFFSET.y = 0` in this task, both lines reduce to `CENTER_Y` — layout unchanged.)

- [ ] **Step 3: Replace `_make_position(anchor_x: float) -> Vector2` to take a `Vector2`**

Find `_make_position` (currently lines ~270-272). Replace with:

```gdscript
# Converts a slot anchor (Vector2 center point in container-local space) into
# the card's top-left position. Pivot is at the card's geometric center (set
# in _ready), so this lands the visual center on the anchor. All position
# math MUST route through this — ADR-0001.
func _make_position(anchor: Vector2) -> Vector2:
	return Vector2(anchor.x - CARD_WIDTH / 2.0, anchor.y - CARD_HEIGHT / 2.0)
```

- [ ] **Step 4: Update `_compute_card_transform` for Vector2 lerps**

Find `_compute_card_transform` (currently lines ~218-261). Replace it with:

```gdscript
# THE SEAM. All carousel position/scale/z computation MUST route through this
# function — no inline transform math anywhere else. ADR-0001 records the
# rationale: Phase C's 3D-orbit upgrade replaces this function body wholesale.
#
# state is a Dictionary with keys: from_center (int), to_center (int),
# progress (float 0..1). At-rest states have from_center == to_center.
func _compute_card_transform(card_index: int, state: Dictionary) -> Dictionary:
	var from_role := _slot_role_for(card_index, int(state.from_center))
	var to_role := _slot_role_for(card_index, int(state.to_center))
	var progress: float = state.progress

	var wraps := (from_role == Slot.SIDE_LEFT and to_role == Slot.SIDE_RIGHT) \
		or (from_role == Slot.SIDE_RIGHT and to_role == Slot.SIDE_LEFT)

	var anchor: Vector2
	if wraps:
		if from_role == Slot.SIDE_LEFT:
			# Exits via OFF_LEFT, reappears at OFF_RIGHT, then slides to SIDE_RIGHT.
			if progress < 0.5:
				anchor = _slot_anchor(Slot.SIDE_LEFT).lerp(_slot_anchor(Slot.OFF_LEFT), progress * 2.0)
			else:
				anchor = _slot_anchor(Slot.OFF_RIGHT).lerp(_slot_anchor(Slot.SIDE_RIGHT), (progress - 0.5) * 2.0)
		else:
			# SIDE_RIGHT → exits via OFF_RIGHT, reappears at OFF_LEFT, slides to SIDE_LEFT.
			if progress < 0.5:
				anchor = _slot_anchor(Slot.SIDE_RIGHT).lerp(_slot_anchor(Slot.OFF_RIGHT), progress * 2.0)
			else:
				anchor = _slot_anchor(Slot.OFF_LEFT).lerp(_slot_anchor(Slot.SIDE_LEFT), (progress - 0.5) * 2.0)
	else:
		anchor = _slot_anchor(from_role).lerp(_slot_anchor(to_role), progress)

	# Scale lerps from raw progress, not the piecewise-remapped anchor above.
	# For wrap cards both from_role and to_role are SIDE slots (same scale), so
	# this stays flat — correct. If easing is ever added to progress, revisit.
	var scale_val: float = lerp(_slot_scale(from_role), _slot_scale(to_role), progress)
	var z_val := _slot_z(to_role)

	return {
		"position": _make_position(anchor),
		"scale": Vector2(scale_val, scale_val),
		"z": z_val,
	}
```

- [ ] **Step 5: Update `_start_exit_tween` to use the new `_slot_anchor`**

Find `_start_exit_tween` (currently lines ~145-175). Replace the inner block that computes `target_anchor_x` and `target_position`:

```gdscript
		var role := _slot_role_for(i, picked_index)
		var target_anchor: Vector2
		if role == Slot.SIDE_LEFT:
			target_anchor = _slot_anchor(Slot.OFF_LEFT)
		else:
			target_anchor = _slot_anchor(Slot.OFF_RIGHT)
		var target_position := _make_position(target_anchor)
```

(Just the inner block — the surrounding `_exit_tween = create_tween()...set_parallel(true)...tween_property` stays the same.)

- [ ] **Step 6: Confirm no leftover `_slot_anchor_x` references**

```bash
grep -n "_slot_anchor_x\|SIDE_X_OFFSET\|OFF_SCREEN_X_OFFSET" scripts/ui/answer_carousel.gd
```

Expected: no output. If any of these old names still appear, they're dead references — remove them.

- [ ] **Step 7: Run the full test suite**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
```

Expected: 15/15 carousel, 6/6 baseline. The refactor is layout-neutral (SIDE_OFFSET.y = 0 → cards still lay out horizontally), so all assertions that check `scale.x` still pass. If `test_show_reaction_for_animates_unpicked_cards_out` fails on a position-changes-toward-off-screen assertion, the Vector2 anchor math has a sign error — debug before proceeding.

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/answer_carousel.gd
git commit -m "$(cat <<'EOF'
refactor(carousel): Vector2 slot anchors for the transform seam

_slot_anchor_x(slot) → _slot_anchor(slot) returning Vector2. SIDE_X_OFFSET
+ OFF_SCREEN_X_OFFSET → SIDE_OFFSET + OFF_SCREEN_OFFSET as Vector2
constants (Y component is 0 in this task — Task 6 sets the diagonal tilt
values). _compute_card_transform now uses Vector2.lerp instead of float
lerp for anchors; _make_position takes a Vector2. _start_exit_tween
updated for the new return type. Visually unchanged — pure refactor.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Apply diagonal tilt + add layout tests

Set the Y components of `SIDE_OFFSET` and `OFF_SCREEN_OFFSET` to the starting values from the spec (90 and 270 respectively). After this task, the carousel is visually diagonal at its current (centered) position — Task 7 moves the container to the upper-right.

**Files:**
- Modify: `scripts/ui/answer_carousel.gd` (two constant values)
- Modify: `tests/unit/test_answer_carousel.gd` (add diagonal-layout tests)

- [ ] **Step 1: Add 2 failing tests for the diagonal layout**

Append to `tests/unit/test_answer_carousel.gd`:

```gdscript
# --- Phase 2 Task 6: diagonal layout ---

func test_side_left_anchor_is_below_and_left_of_center():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# SIDE_LEFT card sits down-and-left of center (lower-left of the diagonal).
	# Position of card 0 when card 1 is centered should have x < card 1.x AND y > card 1.y.
	var cards := c.get_cards()
	assert_true(cards[0].position.x < cards[1].position.x, "left side card x should be < center card x")
	assert_true(cards[0].position.y > cards[1].position.y, "left side card y should be > center card y (lower on screen)")

func test_side_right_anchor_is_above_and_right_of_center():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	assert_true(cards[2].position.x > cards[1].position.x, "right side card x should be > center card x")
	assert_true(cards[2].position.y < cards[1].position.y, "right side card y should be < center card y (higher on screen)")
```

- [ ] **Step 2: Run the new tests to confirm they fail (RED)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: the two new tests fail because `SIDE_OFFSET.y = 0` (cards still lay out on a horizontal line). The other 15 tests still pass.

- [ ] **Step 3: Update the constant values in `answer_carousel.gd`**

Find the `SIDE_OFFSET` and `OFF_SCREEN_OFFSET` constants. Update them:

```gdscript
const SIDE_OFFSET := Vector2(140.0, 90.0)         # X = distance to side slot, Y = vertical tilt
const OFF_SCREEN_OFFSET := Vector2(420.0, 270.0)  # X = distance to wrap exit, Y = vertical tilt
```

(Note: `SIDE_OFFSET.x` also changes from 200 to 140 per the spec's starting values. Aspect ratio of the X:Y offset is constant 14:9 across both anchors — keeps the diagonal direction consistent. User tunes these in Phase 5.)

- [ ] **Step 4: Run the test suite to confirm all 17 pass (GREEN)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: 17/17 passed. The two new diagonal tests pass; the existing 15 still pass (scale assertions are unchanged; the `test_show_reaction_for_animates_unpicked_cards_out` position-changing assertion is direction-agnostic — `cards[0].position != start_pos_0` is true whether the position changed horizontally or diagonally).

- [ ] **Step 5: Run the baseline RiddleBox tests for sanity**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
```

Expected: 6/6. No reason for any change.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/answer_carousel.gd tests/unit/test_answer_carousel.gd
git commit -m "$(cat <<'EOF'
feat(carousel): diagonal tilt (L lower-left, R upper-right)

SIDE_OFFSET = (140, 90); OFF_SCREEN_OFFSET = (420, 270). Side cards
now sit on a diagonal axis: SIDE_LEFT below-and-left of center,
SIDE_RIGHT above-and-right. Wrap anchors stay on the same diagonal,
extended further out. Two new tests verify the diagonal layout.

Starting values per spec — final tuning in Phase 5 (PR tail).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Reposition AnswerCarousel container to upper-right play area

Move the carousel container in `scenes/gameplay.tscn` from the old centered-in-riddle-box position to the upper-right play area (~1280, 410). Pure scene edit — no script changes, no test changes.

**Files:**
- Modify: `scenes/gameplay.tscn` (carousel node offsets)

- [ ] **Step 1: Update the AnswerCarousel offsets in `scenes/gameplay.tscn`**

Find the `[node name="AnswerCarousel" parent="."]` block added in Task 4. Replace its offset properties with:

```
[node name="AnswerCarousel" parent="." instance=ExtResource("10_carousel")]
offset_left = 1280.0
offset_top = 410.0
offset_right = 2180.0
offset_bottom = 607.0
```

(`offset_right = offset_left + 900`; `offset_bottom = offset_top + 197`. ResourceID `10_carousel` matches what Task 4 added — keep whatever ID is already there.)

These coordinates place the carousel container's top-left at screen position (1280, 410), so the carousel's CENTER point lands at `(1280 + 450, 410 + 98)` = `(1730, 508)`. With the diagonal tilt from Task 6, the side cards spread up-right and down-left from there, and the right glove (resting at screen position (1760, 920)) has a clean diagonal arc up-and-leftward into the center card.

- [ ] **Step 2: Verify no tests reference absolute screen positions**

```bash
grep -n "1280\|1730\|710\|860\|410" tests/unit/test_answer_carousel.gd
```

Expected: no output. Tests use container-local positions (relative to the AnswerCarousel root), which don't change with the container repositioning. If any test asserts an absolute screen coordinate, it'd need updating — but the porting in Task 3 should have left them all container-local.

- [ ] **Step 3: Run the full test suite**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: same passing count as after Task 6 (17 carousel + 6 baseline + other suites).

- [ ] **Step 4: Manual playtest**

SKIP — you are headless. The user will playtest at the end of Phase 5.

- [ ] **Step 5: Commit**

```bash
git add scenes/gameplay.tscn
git commit -m "$(cat <<'EOF'
feat(carousel): reposition container to upper-right play area

AnswerCarousel offset_left=1280, offset_top=410 — places the carousel
cluster center at ~(1730, 508), in the upper-right play area between
the opponent's silhouette and the right edge. Diagonal tilt from
Task 6 + this position together align the cards on the right glove's
natural punch arc (rest at (1760, 920) → center card at (1730, 508)).

Final container position tuned in Phase 5 per playtest.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Add `PlayerGloves.punch_at_screen_position(target)` + tests

Standalone addition to `PlayerGloves` — new public method that animates the right glove to a target screen position, holds at impact, then returns to rest. Reuses existing `_tween_glove_to` plumbing. The existing `PUNCH_TARGETS`-based Simon attack flow is untouched.

**Files:**
- Modify: `scripts/actors/player_gloves.gd`
- Modify: `tests/unit/test_player_gloves.gd`

- [ ] **Step 1: Add a failing test for the new method**

Append to `tests/unit/test_player_gloves.gd`:

```gdscript
# --- Phase 3 Task 8: punch_at_screen_position ---

const PlayerGlovesScene := preload("res://scenes/actors/player_gloves.tscn")

func _mount_gloves() -> PlayerGloves:
	var g: PlayerGloves = PlayerGlovesScene.instantiate()
	add_child_autoqfree(g)
	return g

func test_punch_at_screen_position_animates_right_glove_to_target():
	var gloves := _mount_gloves()
	await get_tree().process_frame  # _ready completes
	var target := Vector2(1280, 500)
	gloves.punch_at_screen_position(target)
	# Wait for the travel tween to complete (GLOVE_TRAVEL_DURATION + buffer).
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.05).timeout
	var right_pos := gloves.get_node("RightGlove").position
	# Right glove position should be within a few pixels of target after travel completes.
	assert_almost_eq(right_pos.x, target.x, 5.0, "right glove x should reach target")
	assert_almost_eq(right_pos.y, target.y, 5.0, "right glove y should reach target")

func test_punch_at_screen_position_does_not_move_left_glove():
	var gloves := _mount_gloves()
	await get_tree().process_frame
	var left_start := gloves.get_node("LeftGlove").position
	gloves.punch_at_screen_position(Vector2(1280, 500))
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.05).timeout
	var left_pos := gloves.get_node("LeftGlove").position
	# Left glove may sway from IDLE — allow a few pixels.
	assert_almost_eq(left_pos.x, left_start.x, 10.0, "left glove x should not move during right-glove punch")
	assert_almost_eq(left_pos.y, left_start.y, 10.0, "left glove y should not move during right-glove punch")
```

- [ ] **Step 2: Run to confirm the new tests fail (RED)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_player_gloves.gd
```

Expected: parse errors on `PlayerGloves.GLOVE_TRAVEL_DURATION` and `punch_at_screen_position` — neither exists yet. The 4 existing sway-math tests still pass.

- [ ] **Step 3: Add `GLOVE_TRAVEL_DURATION` constant and `punch_at_screen_position` method**

In `scripts/actors/player_gloves.gd`, find the existing `PUNCH_OUT_DURATION := 0.20` line in the animation timings block. Add right after it:

```gdscript
# Used by AnswerCarousel for the K-confirm punch chain. Distinct from
# PUNCH_OUT_DURATION (which serves Simon attack-phase punches into the
# opponent) — carousel punches are shorter because the card is closer.
const GLOVE_TRAVEL_DURATION := 0.15
```

Then add a new public method at the bottom of the file:

```gdscript
# Animates the right glove from its current position to target_pos over
# GLOVE_TRAVEL_DURATION, holds at the target for a single frame (the
# carousel triggers its impact-frame work then), and returns to rest via
# the existing PUNCH_RETURN_DURATION machinery. Unlike _apply_punch_pose,
# this method does not consult PUNCH_TARGETS — the target is supplied by
# the caller (AnswerCarousel, with the chosen card's screen position).
func punch_at_screen_position(target_pos: Vector2) -> void:
	_last_pose_state = State.PUNCH
	_last_pose_direction = -1  # not a Simon direction; carousel-specific
	_set_glove_state(Side.RIGHT, State.PUNCH)
	# Use the existing tween helper so the texture swap + tween bookkeeping
	# stays in one place. Scale and rotation match the glove's base (no
	# inward tilt — the punch is straight at the card cluster).
	_tween_glove_to(
		Side.RIGHT,
		target_pos,
		_right_base_scale,
		_right_base_rotation,
		GLOVE_TRAVEL_DURATION,
		PUNCH_OUT_TRANSITION,
		Tween.EASE_OUT,
	)
	# Schedule the return-to-rest tween for after GLOVE_TRAVEL_DURATION.
	# The carousel fires its impact-frame work on the same beat — the
	# return tween runs in parallel with the picked-card flight.
	await get_tree().create_timer(GLOVE_TRAVEL_DURATION).timeout
	_set_glove_state(Side.RIGHT, State.IDLE)
```

(`_set_glove_state(Side.RIGHT, State.IDLE)` snaps the glove back to base and resumes sway — see the existing code paths for IDLE. The transition is instantaneous because IDLE snaps; if you want a smooth return tween, swap the IDLE call for a `_tween_glove_to(Side.RIGHT, _right_base_position, ..., PUNCH_RETURN_DURATION, ...)` call. The instantaneous snap matches today's behavior for menu_change_item-style instant restores; the smooth return tween matches Simon attack feel. Start with instantaneous; user can tune in Phase 5.)

- [ ] **Step 4: Run the tests to confirm they pass (GREEN)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_player_gloves.gd
```

Expected: 6/6 passed (4 sway-math + 2 new punch tests). If the right glove ends far from the target, check that `_tween_glove_to` is using the right glove's local position (not global) and that the test mounts the gloves scene as a child of the test root.

- [ ] **Step 5: Commit**

```bash
git add scripts/actors/player_gloves.gd tests/unit/test_player_gloves.gd
git commit -m "$(cat <<'EOF'
feat(gloves): add punch_at_screen_position for carousel punches

New public method on PlayerGloves: animates the right glove from
rest to a caller-supplied screen position over GLOVE_TRAVEL_DURATION
(0.15s), then returns to IDLE. Distinct from the Simon attack-phase
PUNCH_TARGETS dict (which the AnswerCarousel will not consult — it
supplies its own target).

Two new tests cover the right-glove-moves and left-glove-untouched
contracts. The existing 4 sway-math tests are unaffected.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Add `_is_punching` gate + glove tween on K-press

Wire the glove punch trigger into the carousel's K-confirm handler. Add `_is_punching` gate that locks all carousel input during the punch chain. In this task, the rest of the existing flow (exit tween, answer_submitted emit) still fires immediately on K-press — Task 10 moves them to the impact frame.

**Files:**
- Modify: `scripts/ui/answer_carousel.gd`
- Modify: `tests/unit/test_answer_carousel.gd` (1 new test)

- [ ] **Step 1: Add a failing test for the punch trigger**

Append to `tests/unit/test_answer_carousel.gd`:

```gdscript
# --- Phase 3 Task 9: glove punch trigger + _is_punching gate ---

const PlayerGlovesScene_Task9 := preload("res://scenes/actors/player_gloves.tscn")

func _mount_carousel_with_gloves() -> Array:
	# Returns [carousel, gloves]. The carousel needs a gloves reference to
	# trigger the punch; tests construct both as siblings under a root.
	var root := Node.new()
	add_child_autoqfree(root)
	var gloves: PlayerGloves = PlayerGlovesScene_Task9.instantiate()
	gloves.name = "PlayerGloves"
	root.add_child(gloves)
	var c: AnswerCarousel = AnswerCarouselScene.instantiate()
	root.add_child(c)
	# Inject the gloves reference via the carousel's setter (added in this task).
	c.set_player_gloves(gloves)
	return [c, gloves]

func test_k_confirm_triggers_glove_punch_and_locks_is_punching():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	var gloves: PlayerGloves = pair[1]
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_false(c._is_punching, "_is_punching should be false before K")
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_true(c._is_punching, "_is_punching should be true after K")
	# Glove should have started traveling toward the picked card's global position.
	var glove_pos := gloves.get_node("RightGlove").position
	assert_true(glove_pos.distance_to(Vector2(1760, 920)) > 5.0, "right glove should have started moving from rest (1760, 920)")
```

- [ ] **Step 2: Run to confirm it fails (RED)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: the new test fails — `set_player_gloves` and `_is_punching` don't exist yet.

- [ ] **Step 3: Add `_is_punching` field and `_player_gloves` reference to `answer_carousel.gd`**

In `scripts/ui/answer_carousel.gd`, add the field near the other tween-state fields (`_fade_tween`, `_exit_tween`):

```gdscript
var _is_punching: bool = false
var _player_gloves: PlayerGloves = null
```

Add a public setter near the other public methods (e.g., right above `display_prompt`):

```gdscript
# Injected by gameplay.tscn wiring — the carousel needs a PlayerGloves
# reference to fire the K-confirm punch chain. If null (e.g., tests that
# don't need the punch behavior), K still emits answer_submitted but no
# glove animation plays.
func set_player_gloves(gloves: PlayerGloves) -> void:
	_player_gloves = gloves
```

- [ ] **Step 4: Update `_unhandled_input` to gate on `_is_punching` and trigger the glove punch**

Replace the early-return guard and the K-confirm branch:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# Lock all carousel input while the cards are still arriving (fade-in)
	# OR while the K-confirm punch chain is in flight.
	if _is_fading_in or _is_punching:
		return
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		var picked := _picked_answers[picked_index]
		_state = State.REACTION
		_is_punching = true
		# Fire the glove punch first; SFX + visual feedback for input
		# acceptance is the swing of the glove. Impact-frame work moves
		# here in Task 10; for now, the existing exit + emit fire immediately.
		_trigger_glove_punch(picked_index)
		_start_exit_tween(picked_index)
		answer_submitted.emit(picked.outcome, picked)

func _trigger_glove_punch(picked_index: int) -> void:
	AudioBus.play_sfx("swing")
	if _player_gloves == null:
		return
	var card := _cards[picked_index]
	# Card's global_position points to its top-left; offset to its visual center.
	var card_center := card.global_position + Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * card.scale
	_player_gloves.punch_at_screen_position(card_center)
```

- [ ] **Step 5: Update `display_prompt` to reset `_is_punching`**

In `display_prompt`, find the block that resets `_is_fading_in`, `_queued_rotation`, etc., and add a line resetting `_is_punching`:

```gdscript
	_is_fading_in = false
	_is_punching = false
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	if _exit_tween:
		_exit_tween.kill()
		_exit_tween = null
```

- [ ] **Step 6: Wire `_player_gloves` in `gameplay.gd`**

In `scripts/gameplay.gd`, find the `_carousel.answer_submitted.connect(_on_answer_submitted)` line added in Task 4. Add right after it:

```gdscript
	_carousel.set_player_gloves($PlayerGloves)
```

- [ ] **Step 7: Run all tests**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_player_gloves.gd
```

Expected: 18 carousel + 6 baseline + 6 gloves all pass. The new `test_k_confirm_triggers_glove_punch_and_locks_is_punching` lands GREEN; older tests are unaffected (most don't supply a gloves reference, and the `set_player_gloves(null)` branch lets K still emit).

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/answer_carousel.gd scripts/gameplay.gd tests/unit/test_answer_carousel.gd
git commit -m "$(cat <<'EOF'
feat(carousel): glove punch trigger on K-confirm (impact-frame work still on K)

K-confirm now fires PlayerGloves.punch_at_screen_position(card_center)
and plays the swing SFX. _is_punching gate locks all carousel input
during the chain (J/L/K all rejected). The rest of the existing flow
(side cards exit, answer_submitted, gameplay outcome handling) still
fires immediately on K-press — Task 10 moves them to the impact frame.

Carousel takes a PlayerGloves reference via set_player_gloves(); if
null (older tests without the wiring), K still emits answer_submitted.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Move impact-frame work to glove-impact

Shift the impact-frame events (SFX pair, card flash, exit tween, `answer_submitted` emit) from K-press time to the moment the glove reaches the card (after `GLOVE_TRAVEL_DURATION`). The picked card begins its flight tween at the same beat — for now, toward a **placeholder** target (Task 11 wires the real opponent body target).

**Files:**
- Modify: `scripts/ui/answer_carousel.gd`
- Modify: `tests/unit/test_answer_carousel.gd` (1 new timing test)

- [ ] **Step 1: Add a failing test for impact-frame timing**

Append to `tests/unit/test_answer_carousel.gd`:

```gdscript
# --- Phase 3 Task 10: impact-frame timing ---

func test_answer_submitted_emits_at_impact_frame_not_at_k_press():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append(Time.get_ticks_msec()))
	var t_press := Time.get_ticks_msec()
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "answer_submitted should NOT emit on K-press")
	# Wait for the glove to reach the card.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.03).timeout
	assert_eq(emitted.size(), 1, "answer_submitted should emit at impact frame")
	var t_emit: int = emitted[0]
	var elapsed_ms := t_emit - t_press
	var expected_ms := int(PlayerGloves.GLOVE_TRAVEL_DURATION * 1000.0)
	assert_true(elapsed_ms >= expected_ms - 30, "emit should be delayed by ~GLOVE_TRAVEL_DURATION — got %dms" % elapsed_ms)
```

- [ ] **Step 2: Run to confirm RED**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: the new test fails — `answer_submitted` fires synchronously today. Confirm before proceeding.

- [ ] **Step 3: Add the new impact-frame constants**

In `scripts/ui/answer_carousel.gd`, add to the animation timings block (after `EXIT_DURATION`):

```gdscript
const CARD_FLIGHT_DURATION  := 0.20
const CARD_FLASH_DURATION   := 0.08
const CARD_FLIGHT_END_SCALE := 0.4
```

- [ ] **Step 4: Add `_card_flight_tween` and `_card_flash_tween` fields**

Below the existing tween fields:

```gdscript
var _card_flight_tween: Tween = null
var _card_flash_tween: Tween = null
```

- [ ] **Step 5: Restructure the K-confirm path to defer impact-frame work**

Replace the `menu_confirm` branch of `_unhandled_input` (added in Task 9):

```gdscript
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		_state = State.REACTION
		_is_punching = true
		# Phase 3 Task 10: glove launches NOW; impact-frame work fires
		# after GLOVE_TRAVEL_DURATION via the await in _do_punch_chain.
		_do_punch_chain(picked_index)
```

Add the new `_do_punch_chain` coroutine method:

```gdscript
# Coroutine: fires the glove launch, waits for impact, then runs the
# impact-frame work (SFX pair, card flash, side-card exit, picked-card
# flight, answer_submitted emit). Stays a single async unit so the
# timing relationships are easy to read.
func _do_punch_chain(picked_index: int) -> void:
	var picked := _picked_answers[picked_index]
	# Launch glove + swing SFX immediately.
	_trigger_glove_punch(picked_index)
	# Wait for the glove to reach the card.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION).timeout
	# IMPACT FRAME — all of these happen on the same beat.
	AudioBus.play_sfx("opponent_punch_body")
	AudioBus.play_sfx("menu_option_select")
	_start_card_flash(picked_index)
	_start_exit_tween(picked_index)
	_start_picked_card_flight(picked_index)
	answer_submitted.emit(picked.outcome, picked)

func _start_card_flash(picked_index: int) -> void:
	var card := _cards[picked_index]
	if _card_flash_tween:
		_card_flash_tween.kill()
		_card_flash_tween = null
	# Spike modulate to white, then decay back over CARD_FLASH_DURATION.
	# Use modulate (not modulate:a) so the flash brightens the texture
	# without changing transparency; the flight tween handles alpha.
	card.modulate = Color(2.0, 2.0, 2.0, card.modulate.a)
	_card_flash_tween = create_tween()
	_card_flash_tween.tween_property(card, "modulate", Color(1.0, 1.0, 1.0, card.modulate.a), CARD_FLASH_DURATION)

func _start_picked_card_flight(picked_index: int) -> void:
	var card := _cards[picked_index]
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	# Phase 3 placeholder target: centered just above the riddle box on
	# the 1920x1080 stage. Task 11 (Phase 4) wires the real opponent body
	# global position. Convert from screen space to the card's parent
	# (the carousel container) local space.
	var screen_target := Vector2(960, 480)
	var local_target := card.get_parent().to_local(screen_target)
	# Adjust by half card width/height + scale so the card's CENTER lands
	# on the target, matching the convention in _make_position.
	var top_left_target := local_target - Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * CARD_FLIGHT_END_SCALE
	_card_flight_tween = create_tween()
	_card_flight_tween.set_parallel(true)
	_card_flight_tween.tween_property(card, "position", top_left_target, CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "scale", Vector2(CARD_FLIGHT_END_SCALE, CARD_FLIGHT_END_SCALE), CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "modulate:a", 0.0, CARD_FLIGHT_DURATION)
	_card_flight_tween.finished.connect(func():
		card.visible = false
	)
```

- [ ] **Step 6: Update `display_prompt` to kill the new tweens on reset**

In `display_prompt`, add to the tween-cleanup block:

```gdscript
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	if _card_flash_tween:
		_card_flash_tween.kill()
		_card_flash_tween = null
```

- [ ] **Step 7: Run all tests**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
```

Expected: 19/19. The new impact-frame timing test passes. Earlier tests still work because the carousel's K-emit timing has only changed — the eventual emit still happens.

If `test_confirm_emits_answer_submitted_with_outcome_and_picked` from Task 3 starts failing because it doesn't wait long enough for the emit, patch it: change `await get_tree().process_frame` after the K-send to `await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.03).timeout`. Same for `test_show_reaction_for_animates_unpicked_cards_out` (but note that `show_reaction_for` is called DIRECTLY in that test, not via K — the test should still pass without changes).

- [ ] **Step 8: Commit**

```bash
git add scripts/ui/answer_carousel.gd tests/unit/test_answer_carousel.gd
git commit -m "$(cat <<'EOF'
feat(carousel): impact-frame timing for the K-confirm chain

K-press now starts a coroutine (_do_punch_chain) that launches the
glove + swing SFX, awaits GLOVE_TRAVEL_DURATION, then fires the
impact-frame work as one beat: opponent_punch_body + menu_option_select
SFX, picked card white-flash + decay over CARD_FLASH_DURATION (0.08s),
side cards exit tween, picked card flight tween (placeholder target at
(960, 480) — Task 11 wires the real opponent body), and
answer_submitted emit.

Picked-card flight: tweens position to placeholder, scale 1.0 →
CARD_FLIGHT_END_SCALE (0.4), alpha 1.0 → 0 over CARD_FLIGHT_DURATION
(0.20s). visible=false at tween end so display_prompt reset is clean.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Wire picked-card flight to opponent body + emit `card_struck_opponent`

Replace the placeholder flight target with the opponent's body global position. Add a new `card_struck_opponent(direction)` signal that fires at the end of the flight tween. Gameplay subscribes and triggers `Opponent.set_action(HIT_LOW, Direction.RIGHT)` then queues `set_action(GUARD_DOWN)` after `HIT_HOLD_DURATION`.

**Files:**
- Modify: `scripts/ui/answer_carousel.gd`
- Modify: `scripts/gameplay.gd`
- Modify: `tests/unit/test_answer_carousel.gd` (1 new signal test)

- [ ] **Step 1: Add a failing test for the `card_struck_opponent` signal**

Append to `tests/unit/test_answer_carousel.gd`:

```gdscript
# --- Phase 4 Task 11: card_struck_opponent signal ---

func test_card_struck_opponent_emits_after_flight_with_direction_right():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	c.card_struck_opponent.connect(func(direction): emitted.append(direction))
	_send_action("menu_confirm")
	# Wait through glove travel + impact + card flight (with slack).
	var total = PlayerGloves.GLOVE_TRAVEL_DURATION + AnswerCarousel.CARD_FLIGHT_DURATION + 0.05
	await get_tree().create_timer(total).timeout
	assert_eq(emitted.size(), 1, "card_struck_opponent should emit once after flight tween completes")
	# Opponent has `enum Direction { LEFT = 0, RIGHT = 1 }` — confirm RIGHT (= 1).
	assert_eq(emitted[0], 1, "direction should be Opponent.Direction.RIGHT (1) — card comes from screen-right")
```

(Note: this test doesn't wire a real Opponent — it only verifies the signal contract. Task 11 step 5 covers the gameplay integration in `scripts/gameplay.gd` which has its own coverage via the existing gameplay tests.)

- [ ] **Step 2: Add the constant and signal to `answer_carousel.gd`**

In the animation timings block:

```gdscript
const HIT_HOLD_DURATION := 0.25
```

At the top of the file, next to `signal answer_submitted`:

```gdscript
# Emitted when the picked card finishes its flight tween into the opponent
# body. The argument is an Opponent.Direction value indicating the side the
# card came from (always RIGHT today — the carousel is on the right of the
# stage). Gameplay forwards to Opponent.set_action(HIT_LOW, direction) and
# queues GUARD_DOWN after HIT_HOLD_DURATION.
signal card_struck_opponent(direction: int)
```

Add an `_opponent_target_callback` field — a callable that returns the opponent body's global screen position. Tests pass `func(): return Vector2(960, 400)` (or similar); gameplay passes a closure capturing `$Opponent.get_node("Body").global_position`:

```gdscript
var _opponent_target_callback: Callable = func(): return Vector2(960, 480)  # default fallback
```

Add a setter:

```gdscript
# Injected by gameplay wiring — supplies the opponent body's global position
# for the picked-card flight target. Default is a center-of-stage fallback
# for tests that don't wire a real opponent.
func set_opponent_target_callback(cb: Callable) -> void:
	_opponent_target_callback = cb
```

- [ ] **Step 3: Update `_start_picked_card_flight` to use the callback target and emit on finish**

Replace `_start_picked_card_flight` from Task 10:

```gdscript
func _start_picked_card_flight(picked_index: int) -> void:
	var card := _cards[picked_index]
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	var screen_target: Vector2 = _opponent_target_callback.call()
	var local_target := card.get_parent().to_local(screen_target)
	var top_left_target := local_target - Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * CARD_FLIGHT_END_SCALE
	_card_flight_tween = create_tween()
	_card_flight_tween.set_parallel(true)
	_card_flight_tween.tween_property(card, "position", top_left_target, CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "scale", Vector2(CARD_FLIGHT_END_SCALE, CARD_FLIGHT_END_SCALE), CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "modulate:a", 0.0, CARD_FLIGHT_DURATION)
	_card_flight_tween.finished.connect(func():
		card.visible = false
		AudioBus.play_sfx("opponent_punch_body")
		# Direction.RIGHT = 1 (matches Opponent.Direction.RIGHT). Card comes
		# from the right side of the stage, so the opponent's hit-pose mirrors
		# to face right via flip_h = (direction == RIGHT).
		card_struck_opponent.emit(1)
	)
```

- [ ] **Step 4: Wire the opponent target callback + `card_struck_opponent` handler in `gameplay.gd`**

In `scripts/gameplay.gd`, find the existing `_carousel.set_player_gloves($PlayerGloves)` line from Task 9. Add right after it:

```gdscript
	# Opponent body global position varies as the opponent lunges/recoils, so
	# capture it lazily per flight via a callback that re-reads the position
	# at the moment the carousel needs it.
	_carousel.set_opponent_target_callback(func(): return $Opponent.get_node("Body").global_position)
	_carousel.card_struck_opponent.connect(_on_card_struck_opponent)
```

Add the new handler near `_on_answer_submitted`:

```gdscript
# Carousel's picked card has landed on the opponent. Show the body_hit_low
# pose (mirrored toward the card's incoming direction), hold HIT_HOLD_DURATION,
# then transition to guard_down. The Opponent.set_action(action, direction)
# signature handles flip_h via direction == RIGHT.
func _on_card_struck_opponent(direction: int) -> void:
	$Opponent.set_action(Opponent.Action.HIT_LOW, direction)
	await get_tree().create_timer(AnswerCarousel.HIT_HOLD_DURATION).timeout
	$Opponent.set_action(Opponent.Action.GUARD_DOWN)
```

- [ ] **Step 5: Update `display_prompt` to reset opponent-related state if needed**

`_card_flight_tween` is already killed in `display_prompt` (added in Task 10). No additional reset needed — `_opponent_target_callback` is stable once set, and the carousel doesn't track opponent state directly.

- [ ] **Step 6: Run all tests**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_player_gloves.gd
```

Expected: 20 carousel + 6 baseline + 6 gloves. All pass.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/answer_carousel.gd scripts/gameplay.gd tests/unit/test_answer_carousel.gd
git commit -m "$(cat <<'EOF'
feat(carousel): card flies to opponent, body_hit_low → guard_down

Picked-card flight target is now $Opponent.get_node("Body").global_position
(via an injected callback so the carousel stays opponent-agnostic).
On flight completion: card visible=false, opponent_punch_body SFX
plays a 2nd time (the impact-on-opponent hit), card_struck_opponent
signal emits with Direction.RIGHT.

Gameplay's _on_card_struck_opponent handler calls
Opponent.set_action(HIT_LOW, RIGHT) — flip_h = true mirrors the pose
to face the card's incoming-from-screen-right direction. After
HIT_HOLD_DURATION (0.25s), transitions to GUARD_DOWN (default
direction, no flip).

Full chain timing: K → ~150ms glove travel → impact frame (side
exit, reaction text, answer_submitted) → ~200ms card flight →
opponent HIT_LOW + 2nd opponent_punch_body SFX → 250ms hold →
GUARD_DOWN. ~600ms K-to-settle total.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Final test sweep, manual playtest checklist, tune + open PR

Carousel + punch chain are feature-complete. This task runs the full test suite one last time, hands the manual playtest checklist to the user (who is the test harness for visual feel per project convention), applies any tuning commits, then pushes and opens the PR.

**Files:**
- Possibly modify: `scripts/ui/answer_carousel.gd` (tuning constants only)
- Possibly modify: `scenes/gameplay.tscn` (carousel container position only)

- [ ] **Step 1: Run the full test suite**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: all tests pass across `test_riddle_box.gd` (6), `test_answer_carousel.gd` (20), `test_player_gloves.gd` (6), and all other suites. If anything fails, fix before opening the PR.

- [ ] **Step 2: Manual playtest checklist — all three opponents**

Launch the game (F5). For each opponent (Tofu, Minty, Sebastian), play at least one full match. Verify:

**Carousel layout:**
- [ ] Cards float in the upper-right play area, diagonal-tilted (L lower-left, R upper-right)
- [ ] Center card overlaps the side cards (z-ordered on top); side cards visible behind
- [ ] No yellow highlight overlay anywhere
- [ ] Riddle box (body text) sits unchanged at the bottom center

**Cycle navigation:**
- [ ] J rotates carousel along the diagonal: center → lower-left, right → center (becomes selected, grows), left → off-screen-low-left → reappears at upper-right
- [ ] L mirrors
- [ ] Wrap-around is visible — the displaced card actually leaves the visible area before coming back
- [ ] Two rapid presses chain; three+ drop

**Visibility:**
- [ ] Cards invisible during typewriter (text-body: Minty / Sebastian)
- [ ] Cards fade in after typing completes; J/L/K locked during fade
- [ ] Cards immediately visible for image-body (Tofu) and NEUTRAL re-display

**Punch chain on K:**
- [ ] Right glove animates from rest into the chosen card
- [ ] Card flashes white on impact, two SFX overlap (`opponent_punch_body` thump + `menu_option_select` chirp)
- [ ] Side cards slide off + fade concurrently with the picked card flying toward the opponent body
- [ ] Picked card lands on opponent → opponent body_hit_low pose (mirrored facing right)
- [ ] After ~250ms hold, opponent transitions to guard_down

**Audio:**
- [ ] `swing` SFX on glove launch
- [ ] `opponent_punch_body` + `menu_option_select` overlap on glove-card impact
- [ ] `opponent_punch_body` again on card-opponent impact
- [ ] Outcome SFX (`riddle_correct`/`_neutral`/`_wrong`) fires as today after `answer_submitted`

**Tofu special path:**
- [ ] No reaction typewriter — riddle box hides on K
- [ ] Punch choreography still plays (glove → card flash → flight → opponent body_hit_low → guard_down)

- [ ] **Step 3: Tune if needed**

Based on the playtest, adjust the tuning constants in `scripts/ui/answer_carousel.gd`:

- If diagonal tilt feels too steep / shallow → adjust `SIDE_OFFSET.y` and `OFF_SCREEN_OFFSET.y` (currently 90 / 270; keep their ratio constant for axis consistency)
- If side cards too close / too far from center → adjust `SIDE_OFFSET.x` (140; keep `OFF_SCREEN_OFFSET.x` proportional, currently 420)
- If glove travel feels sluggish / snappy → adjust `PlayerGloves.GLOVE_TRAVEL_DURATION` (0.15)
- If card flight feels too fast / slow → adjust `CARD_FLIGHT_DURATION` (0.20) or `CARD_FLIGHT_END_SCALE` (0.4)
- If hit-hold too long / short → adjust `HIT_HOLD_DURATION` (0.25)
- If wrap-around card teleports visibly → increase `OFF_SCREEN_OFFSET.x` / `OFF_SCREEN_OFFSET.y` proportionally

If the carousel container needs to move, edit `scenes/gameplay.tscn` (`offset_left`, `offset_top` on the AnswerCarousel node).

Commit any tuning changes:

```bash
git add scripts/ui/answer_carousel.gd scenes/gameplay.tscn
git commit -m "$(cat <<'EOF'
tune(carousel): playtest adjustments

[Describe what was tuned and why — e.g., "side cards felt too cramped
at SIDE_OFFSET.x=140; bumped to 160. Card flight felt too floaty;
trimmed to 0.16s." If multiple constants tuned, list each.]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If no tuning needed, skip this step.

- [ ] **Step 4: Push the branch and open the PR**

```bash
git push -u origin feature/carousel-3d-orbit-and-punch
gh pr create --title "feat(carousel): 3D orbit + glove-punch choreography" --body "$(cat <<'EOF'
## Summary

- Extracts the answer carousel from `RiddleBox` into a standalone `AnswerCarousel` scene+script (sibling in `gameplay.tscn`), so `RiddleBox` is now body-only.
- Repositions the carousel cluster to the upper-right play area (~(1730, 508) center) with a diagonal-tilt layout (L lower-left, M center, R upper-right) — see [design doc](docs/superpowers/specs/2026-05-23-carousel-3d-orbit-and-punch-design.md).
- K-confirm triggers a punch chain: right glove travels to chosen card (`swing` SFX), impact-frame fires SFX pair (`opponent_punch_body` + `menu_option_select`) + card flash + side-card exit + reaction text, picked card flies into opponent body, opponent reacts `body_hit_low` (mirrored right) → `guard_down` after `HIT_HOLD_DURATION`.

## Architecture

- ADR-0001's `_compute_card_transform` + `_make_position` seam discipline preserved — Vector2 anchors swap is contained to the seam functions.
- New `PlayerGloves.punch_at_screen_position(target)` method (existing Simon `PUNCH_TARGETS` flow untouched).
- New signals: `AnswerCarousel.answer_submitted(outcome, picked_answer)` replaces `RiddleBox.answer_submitted(outcome)`; `AnswerCarousel.card_struck_opponent(direction)` wires opponent reaction.

## Test plan

- [x] All GUT tests pass (`test_riddle_box.gd` 6/6, `test_answer_carousel.gd` 20/20, `test_player_gloves.gd` 6/6)
- [x] Manual playtest across all three opponents per the checklist in `docs/superpowers/plans/2026-05-23-carousel-3d-orbit-and-punch.md` Task 12

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 5: Verify the PR opened cleanly and link it back**

```bash
gh pr view --web
```

PR URL is printed; share it with the user.

---

## Self-Review (run before claiming this plan complete)

This checklist gets run by the plan author after writing, not by an executor.

**1. Spec coverage**

| Locked decision | Task |
|---|---|
| Extract carousel from RiddleBox into AnswerCarousel scene+script | Task 2 (create), Task 4 (slim RiddleBox + wire gameplay) |
| `_compute_card_transform` + `_make_position` seam preserved in new file | Task 2 (carry-over), Task 5 (Vector2 refactor) |
| Slot anchors become Vector2 | Task 5 |
| Diagonal tilt L lower-left, R upper-right | Task 6 |
| Carousel container in upper-right play area | Task 7 |
| Overlap between center and side cards | Task 6 (SIDE_OFFSET.x=140 produces ~60px overlap given SIDE_SCALE=0.7) |
| New `PlayerGloves.punch_at_screen_position(target)` | Task 8 |
| `_is_punching` gate on carousel input | Task 9 |
| Glove launches on K, `swing` SFX | Task 9 |
| Impact frame: SFX pair + flash + side exit + flight + answer_submitted + reaction routing | Task 10 (carousel side), Task 4 (gameplay's show_reaction/hide routing) |
| Picked card flies to opponent body global position | Task 11 |
| `card_struck_opponent(direction)` signal | Task 11 |
| Opponent body_hit_low (mirrored) → guard_down after HIT_HOLD_DURATION | Task 11 (gameplay handler) |
| Tofu empty-reaction path: punch still plays, riddle box hides | Task 4 (gameplay's `if picked.has_reaction(): ... else: _riddle.hide()`) + Task 11 (chain runs regardless) |
| Test split: test_riddle_box.gd slimmed, test_answer_carousel.gd new | Tasks 3 + 4 |
| test_player_gloves.gd extended | Task 8 |
| CONTEXT.md updates | Task 1 |
| Single branch + single PR, 4-phase rollout | Branch already exists; tasks grouped per phase; Task 12 opens PR |
| Tuning pass after all phases land | Task 12 step 3 |

All locked spec items have a corresponding task.

**2. Placeholder scan**

Searched for: "TBD", "TODO", "fill in details", "implement later". None in the plan body. Two intentional `placeholder` uses in Task 10 (Phase 3's interim card-flight target) — these are explicit staging that Task 11 replaces with the real target, called out in the task body.

**3. Type consistency**

- `AnswerCarousel.answer_submitted` signal signature: `(outcome: int, picked: DialogueAnswer)` — consistent in Task 2 (declaration), Task 4 (gameplay handler signature `_on_answer_submitted(outcome: int, picked: DialogueAnswer)`), Task 3 (test connect lambda).
- `AnswerCarousel.card_struck_opponent` signal: `(direction: int)` — consistent in Task 11.
- `RiddleBox.show_reaction(reaction_text: String)` — consistent in Task 4.
- `PlayerGloves.punch_at_screen_position(target_pos: Vector2)` — consistent in Task 8.
- `PlayerGloves.GLOVE_TRAVEL_DURATION` constant — declared in Task 8, referenced in Task 9 (test wait), Task 10 (await timer), Task 11 (test wait).
- `AnswerCarousel.CARD_FLIGHT_DURATION`, `HIT_HOLD_DURATION` — declared in Tasks 10/11, referenced in test wait timers in the same tasks.
- `_slot_anchor(slot) -> Vector2` — replaces `_slot_anchor_x(slot) -> float` in Task 5; all call sites (`_compute_card_transform`, `_start_exit_tween`) updated in same task.
- `_make_position(anchor: Vector2)` — signature change in Task 5; same task updates `_compute_card_transform` and `_start_exit_tween` call sites.
- `set_player_gloves(gloves: PlayerGloves)` — declared in Task 9, called in Task 9 (gameplay wiring), Task 11 leaves it intact.
- `set_opponent_target_callback(cb: Callable)` — declared in Task 11.
- `_carousel`, `_riddle` field names in `gameplay.gd` — `_carousel` added in Task 4, used consistently in Tasks 9, 11.

No inconsistencies found.

---

End of plan.
