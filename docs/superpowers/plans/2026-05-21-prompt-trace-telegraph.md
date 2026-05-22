# Prompt Trace Telegraph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-shot chase-light border trace to `WasdPrompt`'s PROMPT-variant entry, making incoming-attack telegraphing more visible.

**Architecture:** New `TraceBorder` `Control` child node on `WasdPrompt`, anchored full-rect. Custom `_draw()` renders a 24-segment gradient tail behind a head point that traces the perimeter over 0.20s. Triggered only by `WasdPrompt._animate_prompt_pulse(...)`; the four other variants (SUCCESS, FAIL, SUCCESS_ATTACK, FAIL_ATTACK) skip it.

**Tech Stack:** Godot 4 / GDScript / GUT test framework. No shaders, no new assets.

**Spec:** `docs/superpowers/specs/2026-05-21-prompt-trace-telegraph-design.md`

---

## File Structure

- **Create:** `scripts/ui/trace_border.gd` — owns `_perimeter_point`, `_trail_color`, `play_trace`, `stop_trace`, `_process`, `_draw`.
- **Create:** `tests/unit/test_trace_border.gd` — GUT tests for perimeter math, color sampling, and play/stop state.
- **Modify:** `scenes/ui/wasd_prompt.tscn` — add `TraceBorder` child between `Background` and `Label`.
- **Modify:** `scripts/ui/wasd_prompt.gd` — cache `_trace`, call `play_trace()` from `_animate_prompt_pulse`, call `stop_trace()` from `hide_prompt`/`_reset_to_clean_state`.
- **Modify:** `tests/unit/test_wasd_prompt_animation.gd` — add variant-gating tests.

---

## Task 1: TraceBorder math helpers (perimeter + color)

**Files:**
- Create: `scripts/ui/trace_border.gd`
- Create: `tests/unit/test_trace_border.gd`

- [ ] **Step 1.1: Write failing tests for perimeter sampling and color sampling**

Create `tests/unit/test_trace_border.gd`:

```gdscript
extends GutTest

const TB = preload("res://scripts/ui/trace_border.gd")

func _make_trace(w: float, h: float) -> Node:
	var tb = TB.new()
	tb.size = Vector2(w, h)
	return tb

func test_perimeter_zero_is_origin():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.0), Vector2(0.0, 0.0))

func test_perimeter_quarter_is_top_right():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.25), Vector2(188.0, 0.0))

func test_perimeter_half_is_bottom_right():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.5), Vector2(188.0, 188.0))

func test_perimeter_three_quarters_is_bottom_left():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(0.75), Vector2(0.0, 188.0))

func test_perimeter_one_wraps_to_origin():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(1.0), Vector2(0.0, 0.0))

func test_perimeter_wraps_when_t_exceeds_one():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._perimeter_point(1.5), tb._perimeter_point(0.5))

func test_perimeter_wraps_when_t_negative():
	var tb = _make_trace(188.0, 188.0)
	# -0.25 % 1.0 = 0.75 → bottom-left
	assert_eq(tb._perimeter_point(-0.25), Vector2(0.0, 188.0))

func test_trail_color_head_is_opaque_white():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(0), TB._HEAD_COLOR)

func test_trail_color_tail_end_is_transparent_violet():
	var tb = _make_trace(188.0, 188.0)
	assert_eq(tb._trail_color(TB._SEGMENT_COUNT - 1), TB._TAIL_COLOR)

func test_trail_color_midpoint_alpha_between_zero_and_one():
	var tb = _make_trace(188.0, 188.0)
	var mid = TB._SEGMENT_COUNT / 2
	var c = tb._trail_color(mid)
	assert_gt(c.a, 0.0, "mid alpha must be > 0")
	assert_lt(c.a, 1.0, "mid alpha must be < 1")
```

- [ ] **Step 1.2: Run the tests to confirm they fail**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_trace_border.gd -gexit`
Expected: FAIL — `trace_border.gd` does not exist; test cannot load.

- [ ] **Step 1.3: Create `scripts/ui/trace_border.gd` with constants and helpers**

```gdscript
class_name TraceBorder
extends Control

# Tuning constants — see docs/superpowers/specs/2026-05-21-prompt-trace-telegraph-design.md
const _LAP_SECONDS := 0.20
const _TAIL_FRACTION := 1.0 / 3.0
const _SEGMENT_COUNT := 24
const _LINE_THICKNESS := 5.0
const _HEAD_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const _MID_COLOR := Color(1.0, 0.15, 0.75, 1.0)
const _TAIL_COLOR := Color(0.55, 0.10, 0.85, 0.0)

# Returns the (x, y) point on the box perimeter for normalized t ∈ [0, 1).
# Clockwise from top-left: top edge → right edge → bottom edge → left edge.
# t wraps via fposmod, so negative or > 1.0 inputs map back into [0, 1).
func _perimeter_point(t: float) -> Vector2:
	var w := size.x
	var h := size.y
	var perimeter := 2.0 * (w + h)
	var u := fposmod(t, 1.0) * perimeter
	if u < w:
		return Vector2(u, 0.0)
	if u < w + h:
		return Vector2(w, u - w)
	if u < 2.0 * w + h:
		return Vector2(w - (u - w - h), h)
	return Vector2(0.0, h - (u - 2.0 * w - h))

# Returns the color for trail segment i ∈ [0, _SEGMENT_COUNT).
# i = 0 is the head, i = _SEGMENT_COUNT - 1 is the tail end.
# Linear interp head → mid (first half), then mid → tail (second half).
func _trail_color(i: int) -> Color:
	var u := float(i) / float(_SEGMENT_COUNT - 1)
	if u < 0.5:
		return _HEAD_COLOR.lerp(_MID_COLOR, u * 2.0)
	return _MID_COLOR.lerp(_TAIL_COLOR, (u - 0.5) * 2.0)
```

- [ ] **Step 1.4: Run the tests to confirm they pass**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_trace_border.gd -gexit`
Expected: PASS on all 10 tests.

- [ ] **Step 1.5: Commit**

```bash
git add scripts/ui/trace_border.gd tests/unit/test_trace_border.gd
git commit -m "feat(ui): add TraceBorder perimeter and color helpers"
```

---

## Task 2: TraceBorder state machine (play, stop, process)

**Files:**
- Modify: `scripts/ui/trace_border.gd`
- Modify: `tests/unit/test_trace_border.gd`

- [ ] **Step 2.1: Append failing tests for play_trace / stop_trace / process advancement**

Append to `tests/unit/test_trace_border.gd`:

```gdscript
func test_play_trace_activates_and_resets_progress():
	var tb = _make_trace(188.0, 188.0)
	tb._progress = 0.7
	tb._active = false
	tb.play_trace()
	assert_true(tb._active, "play_trace must set _active = true")
	assert_eq(tb._progress, 0.0, "play_trace must reset _progress to 0")

func test_stop_trace_deactivates():
	var tb = _make_trace(188.0, 188.0)
	tb._active = true
	tb._progress = 0.5
	tb.stop_trace()
	assert_false(tb._active, "stop_trace must set _active = false")

func test_process_advances_progress_when_active():
	var tb = _make_trace(188.0, 188.0)
	tb.play_trace()
	tb._advance(0.05)  # 0.05 / 0.20 = 0.25
	assert_almost_eq(tb._progress, 0.25, 0.001)
	assert_true(tb._active)

func test_process_deactivates_when_progress_reaches_one():
	var tb = _make_trace(188.0, 188.0)
	tb.play_trace()
	tb._advance(TB._LAP_SECONDS)
	assert_false(tb._active, "_active must clear once a full lap completes")

func test_process_noop_when_inactive():
	var tb = _make_trace(188.0, 188.0)
	tb._active = false
	tb._progress = 0.0
	tb._advance(0.10)
	assert_eq(tb._progress, 0.0, "_advance must not move progress when inactive")
```

(Tests call `_advance(delta)`, a thin synchronous wrapper around the same logic `_process(delta)` uses. This lets us drive the state machine without needing the SceneTree to deliver process ticks.)

- [ ] **Step 2.2: Run the new tests to confirm they fail**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_trace_border.gd -gexit`
Expected: FAIL on the five new tests — `play_trace`, `stop_trace`, `_advance`, `_active`, `_progress` undefined.

- [ ] **Step 2.3: Add state, play/stop, and `_advance` to `trace_border.gd`**

Append below the existing constants/helpers in `scripts/ui/trace_border.gd`:

```gdscript
var _active: bool = false
var _progress: float = 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func play_trace() -> void:
	_progress = 0.0
	_active = true
	queue_redraw()

func stop_trace() -> void:
	_active = false
	queue_redraw()

func _process(delta: float) -> void:
	if not _active:
		return
	_advance(delta)
	queue_redraw()

# Pure state-machine step extracted from _process so unit tests can drive
# progress without depending on the SceneTree.
func _advance(delta: float) -> void:
	if not _active:
		return
	_progress += delta / _LAP_SECONDS
	if _progress >= 1.0:
		_progress = 1.0
		_active = false
```

- [ ] **Step 2.4: Run the tests to confirm they pass**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_trace_border.gd -gexit`
Expected: PASS on all 15 tests (10 from Task 1 + 5 new).

- [ ] **Step 2.5: Commit**

```bash
git add scripts/ui/trace_border.gd tests/unit/test_trace_border.gd
git commit -m "feat(ui): add TraceBorder play/stop state machine"
```

---

## Task 3: TraceBorder drawing and scene wiring

**Files:**
- Modify: `scripts/ui/trace_border.gd` (add `_draw`)
- Modify: `scenes/ui/wasd_prompt.tscn` (add `TraceBorder` child)

This task is visual — there is no unit test for `_draw()` output (GUT can't assert on rendered pixels). Verification is by playtest at Task 5.

- [ ] **Step 3.1: Implement `_draw` in `trace_border.gd`**

Append to `scripts/ui/trace_border.gd`:

```gdscript
# Draws _SEGMENT_COUNT short line segments behind the head, each spanning
# (_TAIL_FRACTION / _SEGMENT_COUNT) of the perimeter. Color is sampled per
# segment so the head reads as opaque white and the tail end as transparent
# violet.
func _draw() -> void:
	if not _active:
		return
	var seg_span := _TAIL_FRACTION / float(_SEGMENT_COUNT)
	for i in _SEGMENT_COUNT:
		var t_start := _progress - float(i) * seg_span
		var t_end := _progress - float(i + 1) * seg_span
		var a := _perimeter_point(t_start)
		var b := _perimeter_point(t_end)
		draw_line(a, b, _trail_color(i), _LINE_THICKNESS)
```

- [ ] **Step 3.2: Add `TraceBorder` child to `scenes/ui/wasd_prompt.tscn`**

Open `scenes/ui/wasd_prompt.tscn` and add an `ext_resource` for the new script and a `TraceBorder` node between `Background` and `Label`.

After the existing `[ext_resource ... id="1_wasd"]` line, add:

```
[ext_resource type="Script" path="res://scripts/ui/trace_border.gd" id="2_trace"]
```

After the `[node name="Background" ...]` block and before the `[node name="Label" ...]` block, insert:

```
[node name="TraceBorder" type="Control" parent="."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("2_trace")
```

- [ ] **Step 3.3: Confirm the existing tests still pass (no regression from `_draw`)**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_trace_border.gd -gexit`
Expected: PASS on all 15 tests.

- [ ] **Step 3.4: Commit**

```bash
git add scripts/ui/trace_border.gd scenes/ui/wasd_prompt.tscn
git commit -m "feat(ui): TraceBorder _draw + wire into wasd_prompt scene"
```

---

## Task 4: Hook TraceBorder into WasdPrompt PROMPT pulse

**Files:**
- Modify: `scripts/ui/wasd_prompt.gd`
- Modify: `tests/unit/test_wasd_prompt_animation.gd`

- [ ] **Step 4.1: Write failing test that PROMPT variant activates the trace and other variants do not**

Append to `tests/unit/test_wasd_prompt_animation.gd`:

```gdscript
const WP_SCENE = preload("res://scenes/ui/wasd_prompt.tscn")

func test_prompt_variant_plays_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.PROMPT, 0.5)
	await get_tree().process_frame
	assert_true(wp._trace._active, "PROMPT variant must activate trace")
	wp.hide_prompt()

func test_success_variant_does_not_play_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.SUCCESS, 0.5)
	await get_tree().process_frame
	assert_false(wp._trace._active, "SUCCESS variant must NOT activate trace")
	wp.hide_prompt()

func test_fail_variant_does_not_play_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.FAIL, 0.5)
	await get_tree().process_frame
	assert_false(wp._trace._active, "FAIL variant must NOT activate trace")
	wp.hide_prompt()

func test_success_attack_variant_does_not_play_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.SUCCESS_ATTACK, 0.5)
	await get_tree().process_frame
	assert_false(wp._trace._active, "SUCCESS_ATTACK variant must NOT activate trace")
	wp.hide_prompt()

func test_fail_attack_variant_does_not_play_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.FAIL_ATTACK, 0.5)
	await get_tree().process_frame
	assert_false(wp._trace._active, "FAIL_ATTACK variant must NOT activate trace")
	wp.hide_prompt()

func test_hide_prompt_stops_trace():
	var wp = WP_SCENE.instantiate()
	add_child_autofree(wp)
	await get_tree().process_frame
	wp.display(SimonSequence.Direction.HEAD, WP.Variant.PROMPT, 0.5)
	await get_tree().process_frame
	assert_true(wp._trace._active)
	wp.hide_prompt()
	assert_false(wp._trace._active, "hide_prompt must stop trace")
```

- [ ] **Step 4.2: Run the new tests to confirm they fail**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_wasd_prompt_animation.gd -gexit`
Expected: FAIL on the six new tests — `wp._trace` is null (no `_trace` field yet).

- [ ] **Step 4.3: Add `_trace` reference and wire calls in `scripts/ui/wasd_prompt.gd`**

Three edits, using surrounding text as anchors (line numbers will drift; do not rely on them).

**Edit A — add the `_trace` onready cache.** Find the line `var _display_generation: int = 0` and add a new line directly below it:

```gdscript
var _display_generation: int = 0
@onready var _trace: TraceBorder = $TraceBorder
```

**Edit B — trigger the trace inside `_animate_prompt_pulse`.** Find the first three lines of `_animate_prompt_pulse` (currently `_reset_to_clean_state()`, `visible = true`, `var total_in := ...`) and insert `_trace.play_trace()` between the reset and `visible = true`:

```gdscript
func _animate_prompt_pulse(duration_seconds: float) -> void:
	_reset_to_clean_state()
	_trace.play_trace()
	visible = true
	var total_in := _PROMPT_PULSE_OUT_SECONDS + _PROMPT_PULSE_SETTLE_SECONDS
```

**Edit C — stop the trace inside `hide_prompt`.** Find `hide_prompt()` and append `_trace.stop_trace()` as the last line of its body:

```gdscript
func hide_prompt() -> void:
	_kill_active_tween()
	_display_generation += 1  # invalidate any in-flight display coroutine
	_reset_to_clean_state()
	visible = false
	_trace.stop_trace()
```

**Edit D — stop the trace inside `_reset_to_clean_state`.** Find `_reset_to_clean_state()` and add `_trace.stop_trace()` as the last line of its body, guarded against `@onready` not having resolved yet (the helper may be called before `_ready` in test contexts):

```gdscript
	if _trace != null:
		_trace.stop_trace()
```

The synchronous stop→play sequence that happens at the start of `_animate_prompt_pulse` (reset → stop → play) is safe: `play_trace()` unconditionally sets `_progress = 0.0` and `_active = true`, so the just-stopped state is immediately overwritten with a fresh trace.

- [ ] **Step 4.4: Run the tests to confirm they pass**

Run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_wasd_prompt_animation.gd -gexit`
Expected: PASS on all tests (the 3 existing constants tests + 6 new variant-gating tests).

- [ ] **Step 4.5: Commit**

```bash
git add scripts/ui/wasd_prompt.gd tests/unit/test_wasd_prompt_animation.gd
git commit -m "feat(ui): wire TraceBorder into WasdPrompt PROMPT pulse"
```

---

## Task 5: Manual playtest verification

No code changes. This task is mandatory before declaring the feature done — `_draw()` correctness can only be confirmed visually.

- [ ] **Step 5.1: Tofu match playtest (slow pace, 0.8s show window)**

Run the project in the Godot editor. Start a Tofu (tier 1) match. Watch the defense show phase. Confirm:
- A bright white-magenta-violet line traces clockwise around the prompt box.
- The trace completes one lap and disappears (no persistent border, no second lap).
- The trace is clearly visible against the yellow background.
- The label letter is never obscured.

- [ ] **Step 5.2: Sebastian match playtest (fast pace, 0.35s show window)**

Switch to Sebastian (tier 3) match. Confirm:
- The trace still completes its lap within the prompt's on-screen window.
- The trace does not visibly clip when the prompt fades out.

- [ ] **Step 5.3: Confirm success/fail flashes have NO trace**

In any match, deliberately fail a block and deliberately succeed at a block. Confirm:
- The damage-flash (FAIL) shows no border trace.
- The block-shake (SUCCESS) shows no border trace.

Then enter an attack phase. Hit a punch correctly and miss one. Confirm:
- The hit-toss (SUCCESS_ATTACK) shows no border trace.
- The miss double-pulse (FAIL_ATTACK) shows no border trace.

- [ ] **Step 5.4: If any of 5.1–5.3 fail, document the issue and return to the relevant task before declaring complete**

Common failure modes and where to look:
- Trace not visible at all → check Z-order of `TraceBorder` in `wasd_prompt.tscn` (must be between `Background` and `Label`).
- Trace draws but doesn't move → check `_process(delta)` is being called (the node may have `process_mode` set incorrectly via the scene).
- Trace appears on success/fail variants → check that `_animate_block_shake` / `_animate_hit_toss` / `_animate_damage_double_pulse` / `_animate_miss_double_pulse` do NOT call `_trace.play_trace()`.
- Trace persists between prompts → check that `hide_prompt()` and `_reset_to_clean_state()` both call `_trace.stop_trace()`.
