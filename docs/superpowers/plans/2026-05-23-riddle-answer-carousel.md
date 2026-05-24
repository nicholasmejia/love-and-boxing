# Riddle Answer Carousel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace direct-index answer selection (J/I/L → indexes 0/1/2 with K confirm) with a two-button carousel (J/L cycle with wrap, K confirms the center card), where the selected card sits at full size in the center and the two unselected cards sit shrunk on either side. Rotation animates with linear-wrap (displaced card slides off the edge and re-enters from the opposite edge). Carousel is hidden during the riddle body typewriter and fades in once typing completes.

**Architecture:** Two phase-commits on a single branch (`feature/riddle-answer-carousel`), one PR. Phase A is a pure input-mapping change with the existing visuals (yellow highlight still drives selection display). Phase B restructures `Layout/Answers` from `HBoxContainer` to a plain `Control` with three absolutely-positioned `AnswerCard` children whose positions, scales, and z-orders are computed exclusively through `_compute_card_transform(card_index, rotation_state)` in `riddle_box.gd` — the single seam that a future Phase C 3D-orbit upgrade will swap. Visibility timing, rotation animation, queue-depth-1 input handling, and side-card exit-on-confirm are layered on top.

**Tech Stack:** Godot 4.6 (Control + Tween), GDScript, GUT 9.x for unit tests. Visual feel (rotation curve, fade duration, scale ratio, slot offsets) is manually playtested per the project's "user is the test harness for visual/feel work" convention; exposed as tuning constants in `riddle_box.gd`.

**Reference docs:**
- `CONTEXT.md` sections: Riddle / Dialogue Prompt, Riddle Render Gate, Reaction State, Riddle Encounter, IJKL vocabulary, Riddle Box + Answer Cards UI Region (all updated this session)
- `docs/adr/0001-riddle-answer-carousel-positioning.md` — records the absolute-positioning + transform-seam choice

---

## File Structure

**Modifies:**
- `scripts/ui/riddle_box.gd` — input mapping (Phase A), then carousel layout + animation + visibility timing (Phase B)
- `scenes/ui/riddle_box.tscn` — `Layout/Answers` HBoxContainer → plain Control (Phase B, Task 3)
- `scenes/ui/answer_card.tscn` — remove `Highlight` ColorRect (Phase B, Task 3)
- `scripts/ui/answer_card.gd` — drop `set_highlighted()` and `_highlight` field (Phase B, Task 3)
- `tests/unit/test_riddle_box.gd` — patch visibility-timing assertions (Phase B, Tasks 5 & 6)

**Creates:**
- `tests/unit/test_riddle_box_carousel.gd` — new file for carousel-specific behaviors (Phase A, grows in later tasks)

**Already on disk from the grilling session (will be committed as Task 1):**
- `CONTEXT.md` — 6 surgical edits
- `scenes/ui/riddle_box.tscn` — body/answers swap (riddle text now below answers in the VBox)
- `docs/adr/0001-riddle-answer-carousel-positioning.md` — new ADR

---

## Task 1: Branch off main, commit the docs-and-swap baseline

Create the feature branch and commit the work that was produced during the grilling session — the CONTEXT.md updates, the body/answers VBox swap in `riddle_box.tscn`, and the new ADR. This becomes the foundation commit; subsequent tasks build code on top of locked-in documentation.

**Files:**
- Modify: `CONTEXT.md` (already done)
- Modify: `scenes/ui/riddle_box.tscn` (already done — VBox order swap only)
- Create: `docs/adr/0001-riddle-answer-carousel-positioning.md` (already done)

- [ ] **Step 1: Create and check out the feature branch**

```bash
git checkout -b feature/riddle-answer-carousel
```

- [ ] **Step 2: Verify the working tree shows exactly the expected baseline changes**

```bash
git status
```

Expected output (paths only):
```
modified:   CONTEXT.md
modified:   scenes/ui/riddle_box.tscn
Untracked files: docs/adr/
```

If anything else appears as modified or untracked, stop and reconcile — extra changes are not part of this baseline.

- [ ] **Step 3: Stage the three files and commit**

```bash
git add CONTEXT.md scenes/ui/riddle_box.tscn docs/adr/0001-riddle-answer-carousel-positioning.md
git commit -m "$(cat <<'EOF'
docs(riddle): lock in Answer Carousel spec + body/answers VBox swap

Updates CONTEXT.md (Prompt, Render Gate, Reaction State, Encounter,
IJKL vocabulary, Riddle Box + Answer Cards UI Region) to describe the
two-button carousel UX, the hide-during-typewriter visibility rule,
and the _compute_card_transform single-seam discipline. Swaps the
VBox order so answers render above the riddle text. Adds ADR-0001
recording the absolute-positioning + transform-seam choice and the
future Phase C 3D-orbit rationale.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify the commit landed cleanly**

```bash
git log --oneline -1 && git status
```

Expected: one new commit, working tree clean.

---

## Task 2: Phase A — Input rebinding (J/L cycle with wrap, I no-op, K unchanged)

Replace the direct-index input mapping (`menu_left` → 0, `menu_up` → 1, `menu_right` → 2) with cyclic navigation (`menu_left` → highlight - 1 mod 3, `menu_right` → highlight + 1 mod 3), make `menu_up` a no-op inside RiddleBox (keep the action bound globally for other menus), and leave `menu_confirm` unchanged. The yellow Highlight ColorRect remains in place as the selection indicator — Phase B removes it.

Create the new `tests/unit/test_riddle_box_carousel.gd` test file with three tests for the new input semantics; existing `test_riddle_box.gd` tests continue to pass.

**Files:**
- Modify: `scripts/ui/riddle_box.gd:119-148` (the `_unhandled_input` body, plus the `_refresh_highlight` helper is untouched)
- Create: `tests/unit/test_riddle_box_carousel.gd`

- [ ] **Step 1: Create the new carousel test file with three failing tests**

Create `tests/unit/test_riddle_box_carousel.gd`:

```gdscript
extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

# Mirrors the helper in test_riddle_box.gd. Inline here so this file is
# self-contained — carousel behavior tests live separately from the
# baseline RiddleBox contract tests.
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

func _mount() -> RiddleBox:
	var box: RiddleBox = RiddleBoxScene.instantiate()
	add_child_autoqfree(box)
	return box

func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

# --- Phase A: cycle input mapping ---

func test_j_decrements_highlight_with_wrap():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# Default highlight is middle (index 1). One J → 0. Another J → 2 (wraps).
	assert_eq(box._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "one J should land on index 0")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 2, "second J should wrap to index 2")

func test_l_increments_highlight_with_wrap():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(box._highlight_index, 1)
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 2, "one L should land on index 2")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "second L should wrap to index 0")

func test_i_is_noop_in_riddle_box():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# Move highlight off the default with one J so we can detect any
	# spurious "snap to middle" behavior.
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0)
	_send_action("menu_up")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "menu_up must not change the highlight inside RiddleBox")
```

- [ ] **Step 2: Run the new tests to confirm they fail (current code maps menu_up → 1)**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: `test_i_is_noop_in_riddle_box` fails because today's code snaps highlight to 1 on menu_up. `test_j_decrements_...` and `test_l_increments_...` likely fail because today's code maps J → 0 directly (so a second J from index 0 stays at 0, not wraps to 2).

- [ ] **Step 3: Replace the input-handling block in `scripts/ui/riddle_box.gd`**

Open `scripts/ui/riddle_box.gd`. The current `_unhandled_input` (lines 119-148) ends at line 148 and looks like:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# menu_change_item fires only when highlight actually moves. Confirm carries
	# no SFX — the riddle outcome SFX (riddle_correct/_neutral/_wrong) is the
	# feedback for picking an answer.
	var new_index: int = _highlight_index
	if event.is_action_pressed("menu_left"):
		new_index = 0
	elif event.is_action_pressed("menu_up"):
		new_index = 1
	elif event.is_action_pressed("menu_right"):
		new_index = 2
	elif event.is_action_pressed("menu_confirm"):
		# Render gate: K-confirm is suppressed while the body typewriter is
		# still running so the player can't skip the read. Navigation stays
		# open — the player can pre-position the highlight while reading.
		if _is_rendering:
			return
		var picked_index := _highlight_index
		# Order matters: show_reaction() must start the reaction typewriter
		# (flipping _is_rendering true, _state to REACTION) BEFORE emit so
		# the gameplay handler can read those flags / await reaction render.
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())
		return
	if new_index != _highlight_index:
		_highlight_index = new_index
		_refresh_highlight()
		AudioBus.play_sfx("menu_change_item")
```

Replace the entire function with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# J/L cycle with wrap; I is intentionally unused inside RiddleBox (per
	# CONTEXT.md Riddle Encounter). Confirm carries no SFX — the riddle
	# outcome SFX (riddle_correct/_neutral/_wrong) is the feedback for
	# picking an answer.
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		# Render gate: K-confirm is suppressed while the body typewriter is
		# still running so the player can't skip the read.
		if _is_rendering:
			return
		var picked_index := _highlight_index
		# Order matters: show_reaction() must start the reaction typewriter
		# (flipping _is_rendering true, _state to REACTION) BEFORE emit so
		# the gameplay handler can read those flags / await reaction render.
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())

func _cycle_highlight(delta: int) -> void:
	_highlight_index = (_highlight_index + delta + _cards.size()) % _cards.size()
	_refresh_highlight()
	AudioBus.play_sfx("menu_change_item")
```

- [ ] **Step 4: Run the new tests to confirm they pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: all 3 tests pass.

- [ ] **Step 5: Run the existing test_riddle_box.gd to confirm no regressions**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
```

Expected: all 9 existing tests pass (unchanged from baseline).

- [ ] **Step 6: Manual playtest — 60-second smoke check**

Launch the game from the Godot editor (F5), start a match, reach a riddle encounter. Verify:
- Default highlight is middle.
- J cycles highlight left with wrap (1 → 0 → 2 → 1 → ...).
- L cycles highlight right with wrap (1 → 2 → 0 → 1 → ...).
- I does nothing.
- K still confirms the highlighted card after typewriter completes.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/riddle_box.gd tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
feat(riddle): two-button cycle nav (J/L wrap, I no-op, K confirms)

Replaces direct-index input mapping with cyclic J/L navigation per
the Answer Carousel design. The Highlight ColorRect remains in place
as the selection indicator — Phase B replaces it with the carousel
center-slot composition.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Phase B-1 — Restructure scene to absolute layout + introduce transform seam

Convert `Layout/Answers` from `HBoxContainer` to plain `Control`. The three `AnswerCard` children become absolutely-positioned with their visual centers at carousel anchor points (center slot at full scale 1.0, side slots at SIDE_SCALE 0.7). Remove the `Highlight` ColorRect from `answer_card.tscn` and its driver code in `answer_card.gd` / `riddle_box.gd`. Introduce `_compute_card_transform(card_index, rotation_state)` as the sole source of card position/scale/z, and call it on display() to lay the cards out. Pressing J/L still snap-swaps which card is at center (no animation yet) by changing `rotation_state.center_index` and re-applying transforms.

After this task: carousel looks right at rest, transitions are jarring snaps (Task 4 adds the tween), highlight is gone (center-card-larger composition replaces its role).

**Files:**
- Modify: `scenes/ui/riddle_box.tscn:65-86` (the Answers HBox subtree)
- Modify: `scenes/ui/answer_card.tscn:25-34` (remove Highlight node)
- Modify: `scripts/ui/answer_card.gd` (drop highlight handling)
- Modify: `scripts/ui/riddle_box.gd` (introduce constants, transform seam, snap-swap on cycle, drop `_refresh_highlight`)

- [ ] **Step 1: Add a failing test for at-rest layout**

Append to `tests/unit/test_riddle_box_carousel.gd`:

```gdscript
# --- Phase B Task 3: at-rest carousel layout ---

func test_display_lays_out_cards_with_center_at_full_scale_sides_shrunk():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := box.get_cards()
	# Middle card (index 1) is the default center → full scale.
	assert_almost_eq(cards[1].scale.x, 1.0, 0.001, "default center card should be at full scale")
	assert_almost_eq(cards[1].scale.y, 1.0, 0.001)
	# Cards 0 and 2 are side cards → SIDE_SCALE.
	assert_almost_eq(cards[0].scale.x, RiddleBox.SIDE_SCALE, 0.001, "left side card should be at SIDE_SCALE")
	assert_almost_eq(cards[2].scale.x, RiddleBox.SIDE_SCALE, 0.001, "right side card should be at SIDE_SCALE")

func test_cycle_swaps_which_card_is_at_full_scale():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Initial: card 1 is center.
	assert_almost_eq(box.get_cards()[1].scale.x, 1.0, 0.001)
	# One L: center_index becomes 2; card 2 should now be at full scale.
	_send_action("menu_right")
	await get_tree().process_frame
	assert_almost_eq(box.get_cards()[2].scale.x, 1.0, 0.001, "after L, card 2 should be at center")
	assert_almost_eq(box.get_cards()[1].scale.x, RiddleBox.SIDE_SCALE, 0.001, "after L, card 1 should be at SIDE_SCALE")
```

- [ ] **Step 2: Run the new tests to confirm they fail**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: the two new tests fail with "Invalid get index 'SIDE_SCALE' on base 'GDScript'" (constant doesn't exist yet) or similar.

- [ ] **Step 3: Modify `scenes/ui/answer_card.tscn` — remove the Highlight node**

Open `scenes/ui/answer_card.tscn`. Delete the entire `[node name="Highlight" type="ColorRect" parent="."]` block (currently lines 25-34, the 10-line block starting with `[node name="Highlight"` and ending before `[node name="Stack"`). The file should go from 69 lines to ~59 lines.

- [ ] **Step 4: Modify `scripts/ui/answer_card.gd` — drop highlight handling**

Replace the entire file with:

```gdscript
class_name AnswerCard
extends Control

@onready var _text: Label = $Stack/Text
@onready var _image: TextureRect = $Stack/Image

var _outcome: int = Outcome.Type.NEUTRAL

func display(answer: DialogueAnswer) -> void:
	_outcome = answer.outcome
	if answer.has_image():
		_image.texture = answer.image
		_image.visible = true
		_text.visible = false
	else:
		_text.text = answer.text
		_text.visible = true
		_image.visible = false

func outcome() -> int:
	return _outcome
```

- [ ] **Step 5: Modify `scenes/ui/riddle_box.tscn` — Answers HBox → plain Control, cards become absolutely-positioned children**

Open `scenes/ui/riddle_box.tscn`. The current `Answers` block (after the body/answers swap from Task 1, this is at lines 24-44 — find the `[node name="Answers"` block) looks like:

```
[node name="Answers" type="HBoxContainer" parent="Layout"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 0
theme_override_constants/separation = 18
alignment = 1

[node name="Left" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 4

[node name="Middle" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 4

[node name="Right" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 4
```

Replace that entire block with:

```
[node name="Answers" type="Control" parent="Layout"]
custom_minimum_size = Vector2(900, 197)
layout_mode = 2
size_flags_horizontal = 4
size_flags_vertical = 0

[node name="Left" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0

[node name="Middle" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0

[node name="Right" parent="Layout/Answers" instance=ExtResource("3_answer")]
layout_mode = 1
anchors_preset = 0
offset_right = 0.0
offset_bottom = 0.0
```

This converts the Answers parent from an HBox to a plain Control with a fixed 900×197 minimum size (matching the previous HBox-implied size, so the surrounding VBox layout is unchanged). The three card children are positioned via script in the next step; their `offset_right`/`offset_bottom` are zeroed because the AnswerCard scene root already supplies `custom_minimum_size = Vector2(288, 197)`.

- [ ] **Step 6: Modify `scripts/ui/riddle_box.gd` — add constants, transform seam, snap-swap, drop highlight**

Open `scripts/ui/riddle_box.gd`. Replace the entire file with:

```gdscript
class_name RiddleBox
extends Control

signal answer_submitted(outcome: int)
# Emitted when a typewriter pass (body OR reaction) finishes naturally.
# Not emitted on early-bail (superseded by a new display/show_reaction) or
# on display_instant. Used by gameplay's Riddle Render Gate to await a
# reaction typewriter from outside RiddleBox.
signal body_render_complete

enum State { NORMAL, REACTION }

# Carousel layout — local to the Answers container Control (900×197).
# All anchor X values are container-local, not viewport-relative.
const CONTAINER_WIDTH := 900.0
const CONTAINER_HEIGHT := 197.0
const CARD_WIDTH := 288.0
const CARD_HEIGHT := 197.0
const CENTER_X := CONTAINER_WIDTH * 0.5
const CENTER_Y := CONTAINER_HEIGHT * 0.5
const SIDE_X_OFFSET := 200.0        # Distance from CENTER_X to side slot anchors
const OFF_SCREEN_X_OFFSET := 600.0  # Distance from CENTER_X to off-screen wrap anchors
const SIDE_SCALE := 0.7
const CENTER_SCALE := 1.0
const CENTER_Z := 10
const SIDE_Z := 0

# A logical slot the card can occupy in the carousel.
enum Slot { OFF_LEFT, SIDE_LEFT, CENTER, SIDE_RIGHT, OFF_RIGHT }

@onready var _body_text: RichTextLabel = $Layout/Body/Text
@onready var _body_image: TextureRect = $Layout/Body/Image
@onready var _cards: Array[AnswerCard] = [
	$Layout/Answers/Left,
	$Layout/Answers/Middle,
	$Layout/Answers/Right,
]

var _highlight_index: int = 1  # Middle slot = default selection (the card whose
                               # current role is Slot.CENTER). Updated by cycle.
var _typewriter_speed: float = 60.0
var _typewriter_generation: int = 0
var _is_rendering: bool = false
var _state: int = State.NORMAL
# Mirror of the picked answer per display, captured at confirm time so
# show_reaction() can read reaction_text without knowing the DialogueAnswer.
var _picked_answers: Array[DialogueAnswer] = []

# Rotation state drives _compute_card_transform. For Task 3 (no animation
# yet), from_center == to_center and progress == 1.0 — i.e., always at-rest.
# Task 4 adds the in-flight tween that interpolates progress 0.0 → 1.0.
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

func is_rendering() -> bool:
	return _is_rendering

# Awaitable. Resolves when the body typewriter completes (or immediately for
# image-body prompts and instant re-displays). Caller is the gate that controls
# when DefensePhase activates — see Riddle Render Gate in CONTEXT.md.
func display(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	if prompt.has_image_body():
		return
	await _start_typewriter(prompt.body_text)

# Synchronous full-text display. Used by the NEUTRAL re-display path where the
# player has already read this prompt — typewriter would be busywork.
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
	for card in _cards:
		card.visible = true
	if prompt.has_image_body():
		_body_image.texture = prompt.body_image
		_body_image.visible = true
		_body_text.visible = false
	else:
		_body_text.visible = true
		_body_image.visible = false
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
	_apply_all_transforms()

# Awaitable. Resolves when the reaction typewriter completes (or immediately
# for empty-reaction prompts, which hide the box).
func show_reaction(picked_index: int) -> void:
	if picked_index < 0 or picked_index >= _picked_answers.size():
		return
	var picked := _picked_answers[picked_index]
	if not picked.has_reaction():
		hide()
		return
	for i in _cards.size():
		_cards[i].visible = (i == picked_index)
	_body_image.visible = false
	_body_text.visible = true
	_state = State.REACTION
	await _start_typewriter(picked.reaction_text)

func _start_typewriter(text: String) -> void:
	_typewriter_generation += 1
	var my_generation := _typewriter_generation
	_is_rendering = true
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

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		if _is_rendering:
			return
		var picked_index := _highlight_index
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())

func _cycle_highlight(delta: int) -> void:
	_highlight_index = (_highlight_index + delta + _cards.size()) % _cards.size()
	_rotation_state.from_center = _rotation_state.to_center
	_rotation_state.to_center = _highlight_index
	_rotation_state.progress = 1.0  # Task 4 will tween 0.0 → 1.0; for now, snap.
	_apply_all_transforms()
	AudioBus.play_sfx("menu_change_item")

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
			# Exits via OFF_LEFT, reappears at OFF_RIGHT, then slides to SIDE_RIGHT.
			if progress < 0.5:
				anchor_x = lerp(_slot_anchor_x(Slot.SIDE_LEFT), _slot_anchor_x(Slot.OFF_LEFT), progress * 2.0)
			else:
				anchor_x = lerp(_slot_anchor_x(Slot.OFF_RIGHT), _slot_anchor_x(Slot.SIDE_RIGHT), (progress - 0.5) * 2.0)
		else:
			# SIDE_RIGHT → exits via OFF_RIGHT, reappears at OFF_LEFT, slides to SIDE_LEFT.
			if progress < 0.5:
				anchor_x = lerp(_slot_anchor_x(Slot.SIDE_RIGHT), _slot_anchor_x(Slot.OFF_RIGHT), progress * 2.0)
			else:
				anchor_x = lerp(_slot_anchor_x(Slot.OFF_LEFT), _slot_anchor_x(Slot.SIDE_LEFT), (progress - 0.5) * 2.0)
	else:
		anchor_x = lerp(_slot_anchor_x(from_role), _slot_anchor_x(to_role), progress)

	var scale_val: float = lerp(_slot_scale(from_role), _slot_scale(to_role), progress)
	# Z is discrete: snap to the to-arrangement's z from frame 1. The new
	# center card rises immediately; the old center drops immediately. Visual
	# correctness comes from scale, not z, during the tween.
	var z_val := _slot_z(to_role)

	# pivot is at card center (set in _ready); position is the card's top-left
	# such that its visual center lands on (anchor_x, CENTER_Y).
	return {
		"position": Vector2(anchor_x - CARD_WIDTH / 2.0, CENTER_Y - CARD_HEIGHT / 2.0),
		"scale": Vector2(scale_val, scale_val),
		"z": z_val,
	}

func _slot_role_for(card_index: int, center_index: int) -> int:
	# Maps card_index relative to which card is currently centered, into a
	# Slot role. Relative offsets: 0 = CENTER, 1 = SIDE_RIGHT, 2 = SIDE_LEFT.
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

Key changes from the Task 2 version:
- Added carousel layout constants, `Slot` enum, `_rotation_state` Dict.
- Added `_ready` to set pivot_offset on each card.
- `_setup_display` resets rotation state and calls `_apply_all_transforms()`.
- `_cycle_highlight` updates rotation state to reflect the snap-swap and re-applies transforms.
- `_refresh_highlight` deleted (no highlight to refresh).
- New helpers: `_apply_all_transforms`, `_compute_card_transform`, `_slot_role_for`, `_slot_anchor_x`, `_slot_scale`, `_slot_z`.

- [ ] **Step 7: Run the carousel tests to confirm the new at-rest layout tests pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: all 5 tests pass (3 input tests from Task 2 + 2 new layout tests).

- [ ] **Step 8: Run the existing test_riddle_box.gd to check for regressions**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
```

Expected: all 9 tests pass. None of these tests touched scale or position, only visibility — which is unchanged in this task.

- [ ] **Step 9: Manual playtest — verify rest layout looks right**

Launch the game (F5), reach a riddle encounter. Verify:
- Three cards visible: the middle one full-size, the two sides smaller (~70%).
- Side cards may overlap with the center card (they're z-ordered behind it). If the side cards are fully separated with no overlap, `SIDE_X_OFFSET` is too large — note for tuning but don't change yet.
- No yellow highlight box.
- Pressing J/L instantly snaps the carousel to a new arrangement (no animation — that's Task 4).
- Reading the riddle and selecting answers still works.

The user will iterate on `SIDE_X_OFFSET`, `SIDE_SCALE`, and `OFF_SCREEN_X_OFFSET` during the final playtest (Task 7). Don't tune in this commit unless something is obviously broken (e.g., cards rendered off-container).

- [ ] **Step 10: Commit**

```bash
git add scripts/ui/riddle_box.gd scripts/ui/answer_card.gd scenes/ui/riddle_box.tscn scenes/ui/answer_card.tscn tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
refactor(riddle): carousel layout via single transform seam, drop highlight

Converts Layout/Answers from HBoxContainer to plain Control with three
absolutely-positioned AnswerCard children. Center card sits at full
scale; side cards sit at SIDE_SCALE 0.7 and are z-ordered behind. All
position/scale/z math routes through _compute_card_transform per
ADR-0001. The Highlight ColorRect is removed — center-slot composition
is the selection indicator. Pressing J/L snap-swaps the rotation state
(no animation yet — Task 4 adds the tween).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Phase B-2 — Rotation animation + queue depth 1 + K-locks-during-animation

Replace the snap-swap in `_cycle_highlight` with a tween that runs `_rotation_state.progress` from 0.0 to 1.0 over `ROTATION_DURATION` seconds, updating all three card transforms each frame via the existing `_compute_card_transform` seam. While a rotation tween is in flight, a second J/L press is buffered (queue depth 1); when the current tween completes, the buffered direction fires immediately. `menu_confirm` (K) is rejected while a tween is in flight — `_is_rendering` already gates K on the typewriter; this task adds a parallel gate on `_is_rotating`. Audio (`menu_change_item`) fires at *input time* (before the tween starts), not at tween-start time — so queued presses are audibly confirmed.

**Files:**
- Modify: `scripts/ui/riddle_box.gd` (replace `_cycle_highlight` body, add `_rotation_tween` field, `_queued_rotation` field, `_is_rotating` flag, new helpers)
- Modify: `tests/unit/test_riddle_box_carousel.gd` (add 3 new tests)

- [ ] **Step 1: Add failing tests for queue + K-lock + rotation duration**

Append to `tests/unit/test_riddle_box_carousel.gd`:

```gdscript
# --- Phase B Task 4: rotation animation + queue + K-lock ---

func test_two_rapid_l_presses_land_on_target_via_queue():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Initial center is index 1. Two L presses: 1 → 2 → 0 (wraps).
	_send_action("menu_right")
	# Don't await — fire the second press while the first tween is in flight.
	_send_action("menu_right")
	# Wait for both tweens: 2 × ROTATION_DURATION + slack.
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION * 2.5).timeout
	assert_eq(box._highlight_index, 0, "two queued L presses should land on index 0 (wrap)")

func test_third_input_during_rotation_is_dropped_not_stacked():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Three rapid L presses: queue depth 1 means we should land on index 0
	# (1 → 2 from first press, 2 → 0 from the queued second; third is dropped).
	_send_action("menu_right")
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION * 2.5).timeout
	assert_eq(box._highlight_index, 0, "third press should be dropped — final index is 0, not 1")

func test_confirm_during_rotation_is_rejected():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	box.answer_submitted.connect(func(o): emitted.append(o))
	# Start a rotation, then press K before it finishes.
	_send_action("menu_right")
	await get_tree().process_frame  # Tween has started; _is_rotating should be true.
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "K during rotation must not emit answer_submitted")
	# After the tween completes, K should be accepted.
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION + 0.05).timeout
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 1, "K after rotation completes should emit answer_submitted")
```

- [ ] **Step 2: Run to confirm the new tests fail**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: the 3 new tests fail because today's `_cycle_highlight` snap-swaps (no tween, no queue, no K-lock). The pre-existing 5 tests still pass.

- [ ] **Step 3: Modify `scripts/ui/riddle_box.gd` — add rotation animation, queue, K-lock**

In `scripts/ui/riddle_box.gd`, add the rotation duration constant in the layout constants block (after `SIDE_Z := 0`):

```gdscript
# Animation timings (seconds). Manually playtested per the project's
# "user is the test harness for visual/feel work" convention.
const ROTATION_DURATION := 0.18
```

Add new fields below `_picked_answers`:

```gdscript
# Rotation animation state. _is_rotating gates K-confirm; _queued_rotation
# buffers exactly one pending J/L press (delta = -1 or +1, 0 means empty).
var _rotation_tween: Tween = null
var _is_rotating: bool = false
var _queued_rotation: int = 0
```

Replace the `_unhandled_input` function so that K-confirm also rejects when `_is_rotating`:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		# Render gate: K-confirm is suppressed while the body typewriter is
		# still running OR while a carousel rotation is in flight (the player
		# can't confirm a card that hasn't fully settled in the center slot).
		if _is_rendering or _is_rotating:
			return
		var picked_index := _highlight_index
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())
```

Replace `_cycle_highlight` with the tween-driven version:

```gdscript
func _cycle_highlight(delta: int) -> void:
	# Audio fires at input time so queued double-taps are audibly confirmed
	# (per the carousel design — see CONTEXT.md Answer Carousel).
	AudioBus.play_sfx("menu_change_item")
	# Update _highlight_index up-front so external observers see the final
	# target immediately. The visual catches up via the tween.
	_highlight_index = (_highlight_index + delta + _cards.size()) % _cards.size()
	if _is_rotating:
		# Queue depth 1: remember the latest direction, drop any earlier
		# queued press. The _highlight_index update above already accounts
		# for both the in-flight target and this queued press, so when the
		# in-flight tween finishes, _start_rotation_to(_highlight_index)
		# picks up the right target.
		_queued_rotation = delta
		return
	_start_rotation_to(_highlight_index)

func _start_rotation_to(target_center: int) -> void:
	_is_rotating = true
	_rotation_state.from_center = _rotation_state.to_center
	_rotation_state.to_center = target_center
	_rotation_state.progress = 0.0
	if _rotation_tween:
		_rotation_tween.kill()
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
		var delta := _queued_rotation
		_queued_rotation = 0
		# _highlight_index already reflects the queued press (it was advanced
		# in _cycle_highlight at queue time). Drive the rotation toward it.
		_start_rotation_to(_highlight_index)
		# Note: we intentionally do NOT re-fire the audio cue here — it
		# already fired at queue time, per the design.
		# We also don't re-advance _highlight_index because that happened
		# at queue time. The `delta` variable is unused; kept for clarity.
		var _unused := delta
```

Also update `_setup_display` to reset rotation state cleanly when a new prompt loads:

In the existing `_setup_display`, find the lines:

```gdscript
	_highlight_index = 1
	_rotation_state.from_center = 1
	_rotation_state.to_center = 1
	_rotation_state.progress = 1.0
	_apply_all_transforms()
```

Replace with:

```gdscript
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
```

- [ ] **Step 4: Run the carousel tests to confirm queue/lock tests pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box_carousel.gd
```

Expected: all 8 tests pass (5 from prior tasks + 3 new).

- [ ] **Step 5: Run the existing test_riddle_box.gd to check for regressions**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_riddle_box.gd
```

Expected: all 9 tests pass. The K-suppression-during-typewriter tests still work because `_is_rotating` is false during typewriter (no rotation in flight) and `_is_rendering` is true.

- [ ] **Step 6: Manual playtest — rotation feel + queue + K-lock**

Launch the game (F5), reach a riddle encounter. Verify:
- Pressing J or L animates the carousel smoothly: the center card slides to a side, the incoming card grows from a side slot, the displaced card slides off-screen and reappears from the opposite edge.
- The wrap-around is visible — the displaced card travels off the screen (or off the riddle box bounds) before coming back, not through the center.
- Pressing L twice quickly results in two rotations playing one after the other, ending two positions to the right.
- Pressing L three or more times quickly drops the third+ presses — final landing is two positions away, not three.
- Pressing K mid-rotation does nothing; pressing K after the rotation completes confirms the center card normally.
- The `menu_change_item` SFX plays on every accepted J/L press (so double-taps produce two cues in quick succession).

The user will tune `ROTATION_DURATION` in the final playtest (Task 7). Don't change it here unless it's obviously broken (e.g., < 0.05s or > 0.5s).

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/riddle_box.gd tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
feat(riddle): carousel rotation tween with queue + K-lock

J/L now animates the carousel rotation (ROTATION_DURATION 0.18s) via
_apply_rotation_progress driving the existing transform seam. Queue
depth 1 buffers one pending J/L during an in-flight tween; further
presses are dropped. K is gated on _is_rotating in addition to
_is_rendering — players cannot confirm a card mid-travel. Audio fires
at input time so queued presses are audibly confirmed.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Phase B-3 — Carousel hidden during typewriter, fade in on completion

Today, cards are visible the frame `display()` is called. New behavior: for text-body prompts that run the typewriter, the three cards' modulate alpha starts at 0 and tweens to 1 over `FADE_IN_DURATION` once the typewriter completes. While alpha < 1, both J/L and K are locked (no rotation or confirmation while the carousel is arriving). Image-body prompts (Tofu) and `display_instant()` (NEUTRAL re-display) skip the fade entirely — cards are immediately visible and operable.

This task changes the contract of `display()` slightly: it now returns *after* the fade-in completes (not just after the typewriter). Code that awaits `display()` in `scripts/gameplay.gd` already treats the resolution as "the player is ready to act," so the extra ~150ms doesn't change behavior — it just shifts which moment "ready to act" means.

**Files:**
- Modify: `scripts/ui/riddle_box.gd` (add FADE_IN_DURATION, `_is_fading_in` flag, modulate handling in display() / display_instant() / _setup_display(), K and J/L lock on `_is_fading_in`)
- Modify: `tests/unit/test_riddle_box.gd` (patch 2 tests — the "all cards visible after display" assertions)
- Modify: `tests/unit/test_riddle_box_carousel.gd` (add 3 new tests for fade behavior + paths that skip fade)

- [ ] **Step 1: Patch the existing test_riddle_box.gd visibility-timing assertions to anticipate the new behavior**

Open `tests/unit/test_riddle_box.gd`. Two tests assert "all cards visible after display." They need to await the body render to complete *and* the fade-in to settle before asserting visibility.

Find `test_display_enters_normal_with_all_cards_visible` (currently lines 23-29):

```gdscript
func test_display_enters_normal_with_all_cards_visible():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
```

Replace with:

```gdscript
func test_display_enters_normal_with_all_cards_visible():
	var box := _mount()
	# display() now resolves after typewriter + fade-in. await the full thing.
	await box.display(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible, "card should be visible after display() resolves")
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "card should be fully opaque after fade-in")
```

Find `test_redisplay_from_reaction_returns_to_normal_with_all_cards` (currently lines 54-65):

```gdscript
func test_redisplay_from_reaction_returns_to_normal_with_all_cards():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(2)
	await get_tree().process_frame
	box.display(prompt)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
```

Replace with:

```gdscript
func test_redisplay_from_reaction_returns_to_normal_with_all_cards():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	box.show_reaction(2)
	await get_tree().process_frame
	# Re-display via display() runs the typewriter + fade again.
	await box.display(prompt)
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
		assert_almost_eq(card.modulate.a, 1.0, 0.01)
```

Also update `test_display_is_awaitable_and_resolves_after_typewriter` (currently lines 69-79) to reflect that display() now resolves after fade-in:

```gdscript
func test_display_is_awaitable_and_resolves_after_typewriter_and_fade():
	var box := _mount()
	# body="body" → 4 chars at default 60 cps ≈ 67ms typewriter, plus
	# FADE_IN_DURATION ≈ 150ms fade-in.
	var prompt := _make_prompt(["r0", "r1", "r2"])
	var t_start := Time.get_ticks_msec()
	await box.display(prompt)
	var elapsed_ms := Time.get_ticks_msec() - t_start
	assert_false(box.is_rendering(), "is_rendering should be false after display() resolves")
	# Resolution must include both the typewriter and the fade-in.
	var min_expected_ms := 30 + int(RiddleBox.FADE_IN_DURATION * 1000.0) - 20
	assert_true(elapsed_ms >= min_expected_ms, "display() should await typewriter + fade — expected ≥%dms, got %dms" % [min_expected_ms, elapsed_ms])
```

(Renamed to make the new contract explicit.)

- [ ] **Step 2: Add new fade-specific tests to test_riddle_box_carousel.gd**

Append to `tests/unit/test_riddle_box_carousel.gd`:

```gdscript
# --- Phase B Task 5: visibility timing ---

func test_cards_invisible_during_typewriter_for_text_body():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	# Sample one frame in — typewriter is running, cards should be alpha 0.
	await get_tree().process_frame
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 0.0, 0.01, "card should be transparent during typewriter")

func test_cards_fade_to_full_opacity_after_typewriter():
	var box := _mount()
	# display() awaits both typewriter and fade-in by Task 5's contract.
	await box.display(_make_prompt(["r0", "r1", "r2"]))
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "card should be fully opaque after display() resolves")

func test_display_instant_skips_fade_cards_immediately_visible():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# No await — display_instant is synchronous and skips the fade.
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "display_instant should show cards at full opacity immediately")

func test_jl_locked_while_fading_in():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	# Wait for typewriter to finish but not the fade.
	await get_tree().create_timer(0.25).timeout
	# Typewriter is done; fade is in flight. _highlight_index should still be 1.
	assert_almost_eq(box.get_cards()[1].modulate.a, 0.0, 0.99, "still fading in (alpha < 1)")  # any value 0..1
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 1, "J/L must be ignored during fade-in")
```

- [ ] **Step 3: Run all tests to confirm the new fade tests fail and existing tests fail in the patched-but-not-implemented direction**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: the 4 new fade tests fail (no fade implementation yet). The 3 patched tests in `test_riddle_box.gd` may pass or fail depending on whether the new `display()` already supports the implied contract — likely they fail on the `modulate.a == 1.0` assertion (cards default to alpha 1.0 today, but the new "invisible during typewriter" assertion in `test_cards_invisible_during_typewriter_for_text_body` is what fails first).

- [ ] **Step 4: Modify `scripts/ui/riddle_box.gd` — add fade-in behavior**

Add `FADE_IN_DURATION` to the animation timings constant block:

```gdscript
const FADE_IN_DURATION := 0.15
```

Add field below `_queued_rotation`:

```gdscript
var _is_fading_in: bool = false
var _fade_tween: Tween = null
```

Modify `_unhandled_input` so that BOTH J/L and K are also gated on `_is_fading_in`:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# Lock all carousel input while the cards are still arriving (typewriter
	# running OR fade-in tween in flight). Per CONTEXT.md Riddle Render Gate,
	# the player cannot navigate or confirm an unsettled carousel.
	if _is_rendering or _is_fading_in:
		return
	if event.is_action_pressed("menu_left"):
		_cycle_highlight(-1)
	elif event.is_action_pressed("menu_right"):
		_cycle_highlight(1)
	elif event.is_action_pressed("menu_confirm"):
		if _is_rotating:
			return
		var picked_index := _highlight_index
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())
```

(The `_is_rendering` check moved up so it gates J/L too, not just K. The reaction-state check above is unchanged.)

Modify `_setup_display` to set initial alpha based on prompt type. Find these lines:

```gdscript
	if prompt.has_image_body():
		_body_image.texture = prompt.body_image
		_body_image.visible = true
		_body_text.visible = false
	else:
		_body_text.visible = true
		_body_image.visible = false
```

Add right below them (before the shuffle / per-card display loop):

```gdscript
	# Text-body prompts start the cards transparent — they fade in after the
	# typewriter completes. Image-body prompts skip the fade (no typewriter).
	var start_alpha: float = 0.0 if not prompt.has_image_body() else 1.0
	for card in _cards:
		card.modulate.a = start_alpha
	_is_fading_in = false
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
```

Modify `display()` to start the fade-in after the typewriter completes:

```gdscript
func display(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	if prompt.has_image_body():
		return
	await _start_typewriter(prompt.body_text)
	await _start_fade_in()
```

Modify `display_instant()` to immediately show cards at full opacity (no fade — they were set to alpha 0 by `_setup_display` if the prompt is text-body, but the instant path skips fade):

```gdscript
func display_instant(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	# display_instant is for the NEUTRAL re-display path — skip the fade,
	# the player has already read and the carousel should be immediately
	# operable. Force cards to full opacity regardless of what _setup_display
	# initialized (which assumed the text-body fade path).
	for card in _cards:
		card.modulate.a = 1.0
	if prompt.has_image_body():
		return
	_typewriter_generation += 1  # cancel any in-flight typewriter
	_is_rendering = false
	_body_text.text = "[center]%s[/center]" % prompt.body_text
	_body_text.visible_characters = -1
```

Add the `_start_fade_in` helper:

```gdscript
func _start_fade_in() -> void:
	_is_fading_in = true
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for card in _cards:
		_fade_tween.tween_property(card, "modulate:a", 1.0, FADE_IN_DURATION)
	await _fade_tween.finished
	_is_fading_in = false
```

- [ ] **Step 5: Run all tests and verify they pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: all tests pass (12 in test_riddle_box_carousel.gd, 9 in test_riddle_box.gd). If the existing test `test_confirm_works_after_typewriter_completes` fails, the issue is timing — that test awaits 0.3s after `display()` starts, which is now not enough (typewriter + fade-in could exceed 300ms). Increase its wait time accordingly:

If you need to patch it, replace its `await get_tree().create_timer(0.3).timeout` with:

```gdscript
	await get_tree().create_timer(0.3 + RiddleBox.FADE_IN_DURATION + 0.05).timeout
```

- [ ] **Step 6: Manual playtest — fade behavior**

Launch the game (F5). Verify across all three opponents:
- **Minty / Sebastian (text-body):** When a riddle encounter starts, the riddle text types out at the top of the riddle box; the answer cards are NOT visible during typing. When typewriting completes, the three cards fade in over ~150ms. Once fully visible, J/L/K all work.
- **Tofu (image-body):** When a riddle encounter starts, the image is immediately visible AND the cards are immediately visible AND J/L/K work immediately (no fade).
- **NEUTRAL re-display:** Pick a NEUTRAL answer. After the reaction text completes and the `NEUTRAL_READ_HOLD` elapses, the same prompt re-displays. The body text appears instantly (no typewriter) AND the cards are immediately visible (no fade) AND J/L/K work immediately.
- During the fade-in for text-body prompts, J/L/K are all ignored. Spam them — nothing should happen until the fade completes.

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/riddle_box.gd tests/unit/test_riddle_box.gd tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
feat(riddle): hide carousel during typewriter, fade in on completion

Text-body prompts now start the answer cards at modulate.a = 0 and
tween them to 1.0 over FADE_IN_DURATION (0.15s) once the body
typewriter completes. Both J/L and K are locked while _is_fading_in
or _is_rendering — the carousel is only operable once fully settled.
Image-body prompts (Tofu) and display_instant() (NEUTRAL re-display)
skip the fade and are immediately operable. display() now resolves
after the fade completes; pre-existing awaiters see no behavior
change beyond the added ~150ms.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Phase B-4 — Side cards animate out on confirm (vs. snap-hide)

Today, `show_reaction` snap-hides the two unpicked cards (`_cards[i].visible = false`). New behavior: the unpicked cards tween out — sliding to their off-screen wrap positions while their modulate alpha drops to 0 — over `EXIT_DURATION` seconds, concurrent with the reaction typewriter starting in the body area. The picked card stays at the center position throughout. Tofu's empty-reaction case (`hide()`) is unchanged.

After the tween completes, the unpicked cards' `visible` flag is set false so re-displays start cleanly. The existing `test_show_reaction_hides_unpicked_cards_and_swaps_body_text` test needs to await the exit tween before asserting end-state visibility.

**Files:**
- Modify: `scripts/ui/riddle_box.gd` (`show_reaction` body — replace snap-hide with exit tween, add `EXIT_DURATION` constant, `_exit_tween` field)
- Modify: `tests/unit/test_riddle_box.gd` (patch one test)
- Modify: `tests/unit/test_riddle_box_carousel.gd` (add one test)

- [ ] **Step 1: Patch the existing visibility test and add the new exit-animation test**

In `tests/unit/test_riddle_box.gd`, find `test_show_reaction_hides_unpicked_cards_and_swaps_body_text` (currently lines 31-42):

```gdscript
func test_show_reaction_hides_unpicked_cards_and_swaps_body_text():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(1)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.REACTION)
	var cards := box.get_cards()
	assert_false(cards[0].visible)
	assert_true(cards[1].visible)
	assert_false(cards[2].visible)
```

Replace with:

```gdscript
func test_show_reaction_hides_unpicked_cards_and_swaps_body_text():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	box.show_reaction(1)
	# show_reaction now tweens unpicked cards out over EXIT_DURATION; wait
	# for that to settle before asserting end-state visibility.
	await get_tree().create_timer(RiddleBox.EXIT_DURATION + 0.05).timeout
	assert_eq(box.get_state(), RiddleBox.State.REACTION)
	var cards := box.get_cards()
	assert_false(cards[0].visible, "unpicked left card should be hidden after exit tween")
	assert_true(cards[1].visible, "picked center card should remain visible")
	assert_false(cards[2].visible, "unpicked right card should be hidden after exit tween")
```

Append to `tests/unit/test_riddle_box_carousel.gd`:

```gdscript
# --- Phase B Task 6: side-card exit on confirm ---

func test_unpicked_cards_animate_out_with_alpha_and_position():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	# Capture starting positions of side cards (index 0 and 2 — middle is picked).
	var cards := box.get_cards()
	var start_pos_0 := cards[0].position
	var start_pos_2 := cards[2].position
	box.show_reaction(1)
	# Sample mid-tween (~half of EXIT_DURATION in).
	await get_tree().create_timer(RiddleBox.EXIT_DURATION * 0.5).timeout
	# Mid-tween: side cards should be partway to off-screen AND partially faded.
	assert_true(cards[0].modulate.a < 0.9, "left card alpha should be tweening down")
	assert_true(cards[2].modulate.a < 0.9, "right card alpha should be tweening down")
	assert_true(cards[0].position != start_pos_0, "left card position should be tweening toward off-screen")
	assert_true(cards[2].position != start_pos_2, "right card position should be tweening toward off-screen")
```

- [ ] **Step 2: Run tests to confirm failures**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: the patched `test_show_reaction_...` may still pass (today's snap-hide ends up at the same visibility state), but the new `test_unpicked_cards_animate_out_...` fails because there's no tween — alpha and position are snap-changed.

- [ ] **Step 3: Modify `scripts/ui/riddle_box.gd` — replace snap-hide with exit tween**

Add `EXIT_DURATION` to the animation timings constant block:

```gdscript
const EXIT_DURATION := 0.18
```

Add field below `_fade_tween`:

```gdscript
var _exit_tween: Tween = null
```

Modify `show_reaction` to tween unpicked cards instead of snap-hiding. The current implementation is:

```gdscript
func show_reaction(picked_index: int) -> void:
	if picked_index < 0 or picked_index >= _picked_answers.size():
		return
	var picked := _picked_answers[picked_index]
	if not picked.has_reaction():
		hide()
		return
	for i in _cards.size():
		_cards[i].visible = (i == picked_index)
	_body_image.visible = false
	_body_text.visible = true
	_state = State.REACTION
	await _start_typewriter(picked.reaction_text)
```

Replace with:

```gdscript
func show_reaction(picked_index: int) -> void:
	if picked_index < 0 or picked_index >= _picked_answers.size():
		return
	var picked := _picked_answers[picked_index]
	if not picked.has_reaction():
		hide()
		return
	_body_image.visible = false
	_body_text.visible = true
	_state = State.REACTION
	# Tween unpicked cards out (slide to their off-screen wrap position +
	# fade alpha to 0). Picked card stays put. Visible flag is flipped after
	# the tween so subsequent display() calls reset cleanly.
	_start_exit_tween(picked_index)
	# Start the reaction typewriter in parallel — exit tween and typewriter
	# run concurrently; await the typewriter (it's the longer of the two,
	# and the existing contract — callers expect reaction typewriter completion).
	await _start_typewriter(picked.reaction_text)

func _start_exit_tween(picked_index: int) -> void:
	if _exit_tween:
		_exit_tween.kill()
	_exit_tween = create_tween()
	_exit_tween.set_parallel(true)
	for i in _cards.size():
		if i == picked_index:
			continue
		var card := _cards[i]
		# Target position: the off-screen anchor on the card's CURRENT side.
		# A card whose visual is left-of-center exits LEFT; right-of-center
		# exits RIGHT. Picked card is always at CENTER, so the others are
		# guaranteed to be at SIDE_LEFT / SIDE_RIGHT (their roles for
		# _rotation_state.to_center == picked_index, which == _highlight_index).
		var role := _slot_role_for(i, _highlight_index)
		var target_anchor_x: float
		if role == Slot.SIDE_LEFT:
			target_anchor_x = _slot_anchor_x(Slot.OFF_LEFT)
		else:
			target_anchor_x = _slot_anchor_x(Slot.OFF_RIGHT)
		var target_position := Vector2(target_anchor_x - CARD_WIDTH / 2.0, CENTER_Y - CARD_HEIGHT / 2.0)
		_exit_tween.tween_property(card, "position", target_position, EXIT_DURATION)
		_exit_tween.tween_property(card, "modulate:a", 0.0, EXIT_DURATION)
	# After the tween, flip visible flags so subsequent _setup_display reset
	# starts from a clean slate. The tween's finished signal fires once all
	# parallel tweens complete.
	_exit_tween.finished.connect(func():
		for i in _cards.size():
			if i != picked_index:
				_cards[i].visible = false
	)
```

- [ ] **Step 4: Run all tests and verify they pass**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: all tests pass. If `test_unpicked_cards_animate_out_...` fails because the cards aren't moving mid-tween, double-check that the `_start_exit_tween` call appears BEFORE the `await _start_typewriter(...)` in `show_reaction` — the exit tween needs to start running before the await suspends.

- [ ] **Step 5: Manual playtest — exit feel + interaction with NEUTRAL re-display**

Launch the game (F5), reach a riddle encounter. Verify:
- Pick an answer with K. The picked card stays in the center; the two unpicked cards slide outward toward the screen edges while fading, taking about 180ms. The reaction text typewriters in the body area concurrently.
- For Tofu (empty-reaction prompts), the entire riddle box just hides on confirm — no exit tween — matching today's behavior (the `if not picked.has_reaction(): hide(); return` branch).
- After a NEUTRAL outcome, when the same prompt re-displays via `display_instant`, all three cards reappear instantly at full opacity in the carousel rest layout. (The exit tween's "set visible=false" must be cleanly reset by `_setup_display`.)
- After a WRONG outcome, when the next prompt loads (via `display()`), all three cards start invisible (alpha 0) and fade in after the typewriter — same as a fresh encounter.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/riddle_box.gd tests/unit/test_riddle_box.gd tests/unit/test_riddle_box_carousel.gd
git commit -m "$(cat <<'EOF'
feat(riddle): unpicked cards tween out on confirm

show_reaction now tweens the two unpicked cards to their off-screen
wrap positions while fading their alpha to 0 over EXIT_DURATION
(0.18s), running concurrently with the reaction typewriter. The
picked card stays at the center slot. After the tween completes,
the unpicked cards' visible flag is flipped so the next display()
or display_instant() reset starts from a clean slate. Tofu's
empty-reaction path (hide() the whole box) is unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Final playtest pass, tuning sweep, open PR

The carousel is feature-complete. This task is a deliberate playtest across all three opponents — Tofu (image-body, no fade), Minty (text-body, NEUTRAL re-display path), Sebastian (text-body, harder pacing) — to validate the *feel*. The tuning constants in `riddle_box.gd` get one round of adjustment based on what the playtest reveals, then the PR opens.

**Files:**
- Possibly modify: `scripts/ui/riddle_box.gd` (tuning constants only — `SIDE_SCALE`, `SIDE_X_OFFSET`, `OFF_SCREEN_X_OFFSET`, `ROTATION_DURATION`, `FADE_IN_DURATION`, `EXIT_DURATION`)

- [ ] **Step 1: Run the full test suite one final time**

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/
```

Expected: all tests pass across `test_riddle_box.gd` and `test_riddle_box_carousel.gd`. If anything fails, fix it before opening the PR — no failing tests in the final commit.

- [ ] **Step 2: Manual playtest checklist — all three opponents**

Launch the game (F5). For each opponent (Tofu, Minty, Sebastian), play at least one full match and verify the following at each riddle encounter:

**Rest layout:**
- [ ] Center card is at full size and on top in z-order
- [ ] Side cards are smaller (~70% scale) and partially behind the center card (overlap visible)
- [ ] No yellow highlight overlay anywhere
- [ ] Layout doesn't break when the side card content is text vs image

**Cycle navigation:**
- [ ] J rotates the carousel: center → left, right → center (becomes selected, grows), left → off-screen-left → reappears from off-screen-right → settles at right slot
- [ ] L is the mirror direction
- [ ] Rotation feels smooth (no stutter)
- [ ] Wrap-around is *visible* — the displaced card actually leaves the visible area before coming back. If the displaced card seems to teleport through the center, increase `OFF_SCREEN_X_OFFSET`.

**Input handling:**
- [ ] Two rapid presses chain into two rotations
- [ ] Three+ rapid presses drop excess (final position is two away, not three)
- [ ] K mid-rotation is ignored; K after rotation completes confirms normally
- [ ] I does nothing (no movement, no sound)

**Visibility (text-body — Minty / Sebastian):**
- [ ] Cards are invisible while the riddle text types out
- [ ] Cards fade in once typing completes
- [ ] During the fade, J/L/K are all locked
- [ ] After the fade, the carousel is fully operable

**Visibility (image-body — Tofu):**
- [ ] Cards are immediately visible at full opacity (no fade)
- [ ] J/L/K work immediately

**NEUTRAL re-display:**
- [ ] After picking a NEUTRAL answer, the reaction text completes
- [ ] Same prompt re-displays instantly (no typewriter), cards immediately visible (no fade), J/L/K work immediately

**Confirm exit animation:**
- [ ] Picked card stays in center
- [ ] Unpicked cards slide outward + fade out concurrently with reaction typewriter
- [ ] For Tofu's empty-reaction prompts: whole box hides cleanly (no broken tween residue)

**Audio:**
- [ ] `menu_change_item` SFX fires on every accepted J/L press (including queued ones)
- [ ] No SFX on I, no SFX on rejected K (during typewriter / fade-in / rotation)

- [ ] **Step 3: Tune if needed**

Based on the playtest, adjust the tuning constants in `scripts/ui/riddle_box.gd`:

- If side cards overlap too much with the center card and unselected text is unreadable → increase `SIDE_X_OFFSET` (e.g., 200 → 240).
- If side cards have a too-large gap from center (no overlap) → decrease `SIDE_X_OFFSET` (e.g., 200 → 160).
- If side cards are too small to read → increase `SIDE_SCALE` (e.g., 0.7 → 0.75).
- If the rotation feels sluggish → decrease `ROTATION_DURATION` (e.g., 0.18 → 0.13).
- If the rotation feels snappy/glitchy → increase `ROTATION_DURATION` (e.g., 0.18 → 0.22).
- If the fade-in feels too slow → decrease `FADE_IN_DURATION`.
- If the wrap-around card seems to teleport visibly (not leave the visible area) → increase `OFF_SCREEN_X_OFFSET`.

Commit any tuning changes:

```bash
git add scripts/ui/riddle_box.gd
git commit -m "$(cat <<'EOF'
tune(riddle): carousel constants per playtest

[Describe what was tuned and why, e.g. "Side cards were unreadable at
0.7 scale; bumped to 0.75. Rotation felt slightly slow; trimmed
duration to 0.15s."]

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

If no tuning needed, skip this step.

- [ ] **Step 4: Push the branch and open the PR**

```bash
git push -u origin feature/riddle-answer-carousel
gh pr create --title "feat(riddle): two-button cycle nav + carousel visuals" --body "$(cat <<'EOF'
## Summary
- Replaces direct-index riddle answer selection (J=left, I=middle, L=right, K=confirm) with a two-button carousel (J/L cycle with wrap, K confirms the center card)
- Restructures `Layout/Answers` from `HBoxContainer` to absolutely-positioned cards routed through a single `_compute_card_transform()` seam — see [ADR-0001](docs/adr/0001-riddle-answer-carousel-positioning.md) for rationale and future Phase C 3D-orbit plan
- Adds rotation tween with queue-depth-1 input handling and K-lock during rotation; hides the carousel during the body typewriter and fades it in once typing completes; tweens unpicked cards out on confirm

## Test plan
- [x] All GUT tests pass (`test_riddle_box.gd` + new `test_riddle_box_carousel.gd`)
- [x] Manual playtest of all three opponents per the checklist in `docs/superpowers/plans/2026-05-23-riddle-answer-carousel.md` Task 7

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
| Two phases, one PR | Tasks 1-7 on a single branch, one PR opened in Task 7 |
| J/L cycle with wrap | Task 2 step 3, `_cycle_highlight` |
| I no-op in RiddleBox | Task 2 step 3 (no menu_up branch in _unhandled_input) |
| Default highlight middle | Task 3 step 6 (`_highlight_index = 1` in `_setup_display`) |
| `menu_change_item` fires on every accepted J/L | Task 2 step 3, Task 4 step 3 (fires at input time before rotation) |
| Absolute layout, drop HBox | Task 3 step 5 (scene edit) |
| Transform seam `_compute_card_transform` | Task 3 step 6 |
| Overlapping coverflow composition (z-ordered) | Task 3 step 6 (`SIDE_Z=0`, `CENTER_Z=10`) |
| Drop Highlight ColorRect | Task 3 steps 3-4 |
| Rotation with linear-wrap | Task 3 step 6 (`_compute_card_transform` wrap logic) + Task 4 step 3 (tween) |
| Queue depth 1 for J/L | Task 4 step 3 (`_queued_rotation`) |
| K locks during rotation animation | Task 4 step 3 (`_is_rotating` check in `_unhandled_input`) |
| Audio fires at input time | Task 4 step 3 (`AudioBus.play_sfx` at top of `_cycle_highlight`) |
| Carousel hidden during typewriter | Task 5 step 4 (`start_alpha = 0.0` in `_setup_display`) |
| Fade in after typewriter | Task 5 step 4 (`_start_fade_in` in `display()`) |
| Tofu (image-body) immediate, no fade | Task 5 step 4 (`start_alpha = 1.0` for `has_image_body()`) |
| NEUTRAL re-display immediate, no fade | Task 5 step 4 (`display_instant` forces alpha 1.0) |
| J/L+K locked during fade-in | Task 5 step 4 (`_is_fading_in` gate in `_unhandled_input`) |
| Side cards animate out on confirm | Task 6 step 3 (`_start_exit_tween`) |
| Test file `test_riddle_box_carousel.gd` | Created in Task 2 step 1, grows through Tasks 3-6 |
| Patch `test_riddle_box.gd` for visibility timing | Task 5 step 1 (two tests), Task 6 step 1 (one test) |
| Tuning constants exposed in `riddle_box.gd` | Task 3 step 6 (layout), Task 4 step 3 (`ROTATION_DURATION`), Task 5 step 4 (`FADE_IN_DURATION`), Task 6 step 3 (`EXIT_DURATION`) |
| ADR committed | Task 1 step 3 |
| Manual playtest with iteration | Task 7 |

All locked spec items have a corresponding task.

**2. Placeholder scan**

Searched for: "TBD", "TODO", "implement later", "fill in details", "appropriate", "add validation", "edge cases", "similar to". None present in this plan.

**3. Type consistency**

- `_compute_card_transform` returns Dict with keys `position`, `scale`, `z` — used consistently in `_apply_all_transforms` and `_apply_rotation_progress` (Tasks 3 and 4).
- `_rotation_state` Dict keys `from_center`, `to_center`, `progress` — used consistently in `_setup_display`, `_start_rotation_to`, `_apply_rotation_progress`, `_compute_card_transform` (Tasks 3 and 4).
- `Slot` enum values referenced consistently across `_slot_role_for`, `_slot_anchor_x`, `_slot_scale`, `_slot_z`, `_compute_card_transform`, `_start_exit_tween` (Tasks 3 and 6).
- `SIDE_SCALE`, `CENTER_SCALE`, `CENTER_Z`, `SIDE_Z`, `CARD_WIDTH`, `CARD_HEIGHT`, `CENTER_X`, `CENTER_Y`, `SIDE_X_OFFSET`, `OFF_SCREEN_X_OFFSET` all defined in Task 3 step 6, referenced in Tasks 3-6.
- `ROTATION_DURATION` defined in Task 4, referenced in Task 4 tests and Task 7 tuning.
- `FADE_IN_DURATION` defined in Task 5, referenced in Task 5 tests and Task 7 tuning.
- `EXIT_DURATION` defined in Task 6, referenced in Task 6 tests and Task 7 tuning.
- `_highlight_index`, `_is_rendering`, `_is_rotating`, `_is_fading_in`, `_queued_rotation` all defined before first use.

No inconsistencies found.

---

End of plan.
