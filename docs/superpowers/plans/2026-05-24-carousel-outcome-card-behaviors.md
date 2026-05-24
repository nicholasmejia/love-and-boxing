# Carousel Outcome-Specific Card Behaviors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single universal punch-chain choreography in `AnswerCarousel` with three per-outcome card animations: RIGHT keeps today's flight-into-opponent + HIT_LOW reaction; NEUTRAL adds a Card Rebound (the picked card bounces screen-right and spins off-screen, opponent stays IDLE); WRONG replaces the side-card exit + picked-card flight with a Card Toss that fans all three cards outward.

**Architecture:** Split `_do_punch_chain` into a shared pre-impact + impact-frame block plus a `match picked.outcome` dispatch to three async helpers (`_run_right_choreography`, `_run_neutral_choreography`, `_run_wrong_choreography`). The existing `card_struck_opponent` signal becomes RIGHT-only — NEUTRAL and WRONG handle their card aftermath internally to the carousel; gameplay's existing WRONG damage path and NEUTRAL re-display path are unchanged. `_start_picked_card_flight` is refactored to accept a Callable `on_landed` so the RIGHT path can emit the signal and the NEUTRAL path can chain into the rebound. Two new local animation helpers (`_animate_card_rebound`, `_animate_card_toss`) own their own tunable constants block.

**Tech Stack:** Godot 4.6 (GDScript), Tween API, GUT 9.x for tests.

---

## File Structure

**Modified:**
- `scripts/ui/answer_carousel.gd` — all production changes live here. Adds: per-outcome dispatch in `_do_punch_chain`, three `_run_*_choreography` helpers, two `_animate_*` helpers with their tuning constants, two new tween member fields (`_card_rebound_tween`, `_card_toss_tweens`). Modifies: `_start_picked_card_flight` to accept a Callable instead of hard-coding the RIGHT-path emit. Updates: the `card_struck_opponent` signal doc-comment.
- `tests/unit/test_answer_carousel.gd` — adds a `_make_prompt_all(outcome)` helper to force the center card to a known outcome, updates the existing `test_card_struck_opponent_emits_after_flight_with_direction_right` to use it, adds two new tests for NEUTRAL and WRONG no-emit behavior.

**Untouched (verified against design):**
- `scripts/gameplay.gd` — `_on_card_struck_opponent` already only fires HIT_LOW + GUARD_DOWN; once the signal only emits on RIGHT, the bug-fix is automatic. The WRONG branch in `_on_answer_submitted` (lines 591-622) already runs the opponent-swings-at-player + damage path. The NEUTRAL branch (623-659) already handles re-display. No gameplay changes needed.
- `scripts/actors/opponent.gd` — no bob freeze; opponent stays in IDLE with Idle Bob continuing on NEUTRAL.
- `CONTEXT.md` — already updated during the grill session (Reaction State expanded; new "Answer Card Animations (per outcome)" subsection under UI Visual Behavior).
- Audio assets — first pass reuses existing SFX. Bespoke card-shatter / soft-thud / tumble cues are a follow-up backlog item.

---

### Task 1: Refactor `_do_punch_chain` to per-outcome dispatch (behavior-preserving)

**Files:**
- Modify: `scripts/ui/answer_carousel.gd:368-419`
- Modify: `tests/unit/test_answer_carousel.gd:293-307` (update one existing test)
- Modify: `tests/unit/test_answer_carousel.gd:1-29` (add `_make_prompt_all` helper)

The point of this task is to extract the dispatch seam without changing observable behavior. All three branches initially route to `_run_right_choreography`, so the player experience is identical. The `_start_picked_card_flight` method is refactored to accept a Callable `on_landed`, so the RIGHT-path emit is now an injected behavior rather than a hard-coded suffix on the flight tween.

- [ ] **Step 1: Add a helper to `test_answer_carousel.gd` that forces all three answers to the same outcome**

Insert this function right below the existing `_make_prompt(reactions)` helper (around line 17):

```gdscript
# Builds a prompt where all three answers carry the same outcome. Lets a test
# K-press any card and know exactly which outcome path the carousel will run,
# bypassing the per-display shuffle in display_prompt.
func _make_prompt_all(outcome: int) -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = "body"
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcome
		a.reaction_text = "r"
		p.answers.append(a)
	return p
```

- [ ] **Step 2: Update the existing RIGHT-emit regression test to force RIGHT outcome**

Replace the body of `test_card_struck_opponent_emits_after_flight_with_direction_right` (currently around lines 294-307) so the prompt always picks RIGHT. With the shuffle in place today, this test happens to pass because today's signal fires on every outcome — once we make the signal RIGHT-only in Task 2/3, an un-forced prompt would flake.

Old body:
```gdscript
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

New body (only the `_make_prompt` → `_make_prompt_all` line changes):
```gdscript
func test_card_struck_opponent_emits_after_flight_with_direction_right():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt_all(Outcome.Type.RIGHT))
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

- [ ] **Step 3: Run the test suite to confirm the updated test still passes against today's code**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gexit
```
Expected: all tests pass. (Today's signal fires for any outcome, including the forced RIGHT.)

- [ ] **Step 4: Refactor `_start_picked_card_flight` to accept an `on_landed` Callable**

In `scripts/ui/answer_carousel.gd`, replace the existing `_start_picked_card_flight` (currently lines 394-419):

Old:
```gdscript
func _start_picked_card_flight(picked_index: int) -> void:
	var card := _cards[picked_index]
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	var screen_target: Vector2 = _opponent_target_callback.call()
	# Control nodes use get_global_transform for coordinate conversion —
	# to_local lives on Node2D, not on Control/CanvasItem in this Godot version.
	var parent_control := card.get_parent() as Control
	var local_target: Vector2 = parent_control.get_global_transform().affine_inverse() * screen_target
	var top_left_target := local_target - Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * CARD_FLIGHT_END_SCALE
	_card_flight_tween = create_tween()
	_card_flight_tween.set_parallel(true)
	_card_flight_tween.tween_property(card, "position", top_left_target, CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "scale", Vector2(CARD_FLIGHT_END_SCALE, CARD_FLIGHT_END_SCALE), CARD_FLIGHT_DURATION)
	# No alpha tween — keep the card fully opaque through the flight so the
	# impact reads visually. The finished lambda below snaps visible=false
	# at landing-time, which is the actual "card hits opponent" moment.
	_card_flight_tween.finished.connect(func():
		card.visible = false
		AudioBus.play_sfx("opponent_punch_body")
		# Direction.RIGHT = 1 (matches Opponent.Direction.RIGHT). Card comes
		# from the right side of the stage, so the opponent's hit-pose mirrors
		# to face right via flip_h = (direction == RIGHT).
		card_struck_opponent.emit(1)
	)
```

New:
```gdscript
# Flies the picked card to the opponent body over CARD_FLIGHT_DURATION.
# At flight end: fires opponent_punch_body SFX, then invokes on_landed.
# on_landed owns everything after the landing beat — hiding the card,
# emitting card_struck_opponent on RIGHT, or kicking off Card Rebound on
# NEUTRAL. WRONG never calls this method (no flight on that path).
func _start_picked_card_flight(picked_index: int, on_landed: Callable) -> void:
	var card := _cards[picked_index]
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	var screen_target: Vector2 = _opponent_target_callback.call()
	# Control nodes use get_global_transform for coordinate conversion —
	# to_local lives on Node2D, not on Control/CanvasItem in this Godot version.
	var parent_control := card.get_parent() as Control
	var local_target: Vector2 = parent_control.get_global_transform().affine_inverse() * screen_target
	var top_left_target := local_target - Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * CARD_FLIGHT_END_SCALE
	_card_flight_tween = create_tween()
	_card_flight_tween.set_parallel(true)
	_card_flight_tween.tween_property(card, "position", top_left_target, CARD_FLIGHT_DURATION)
	_card_flight_tween.tween_property(card, "scale", Vector2(CARD_FLIGHT_END_SCALE, CARD_FLIGHT_END_SCALE), CARD_FLIGHT_DURATION)
	# No alpha tween — keep the card fully opaque through the flight so the
	# impact reads visually.
	_card_flight_tween.finished.connect(func():
		AudioBus.play_sfx("opponent_punch_body")
		on_landed.call()
	)
```

- [ ] **Step 5: Extract `_run_right_choreography` and wire `_do_punch_chain` to a three-branch dispatch**

Replace the existing `_do_punch_chain` (currently lines 368-380):

Old:
```gdscript
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
```

New:
```gdscript
# Coroutine: fires the glove launch, waits for impact, then runs the impact
# frame (SFX pair, card flash, answer_submitted emit). After the emit,
# branches on outcome to one of three card choreographies. The pre-impact
# block stays shared across outcomes — the impact frame is the single sync
# point that every reaction agrees on.
func _do_punch_chain(picked_index: int) -> void:
	var picked := _picked_answers[picked_index]
	# Launch glove + swing SFX immediately.
	_trigger_glove_punch(picked_index)
	# Wait for the glove to reach the card.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION).timeout
	# IMPACT FRAME — shared across outcomes.
	AudioBus.play_sfx("opponent_punch_body")
	AudioBus.play_sfx("menu_option_select")
	_start_card_flash(picked_index)
	answer_submitted.emit(picked.outcome, picked)
	# Per-outcome card choreography.
	match picked.outcome:
		Outcome.Type.RIGHT:
			_run_right_choreography(picked_index)
		Outcome.Type.NEUTRAL:
			_run_right_choreography(picked_index)
		Outcome.Type.WRONG:
			_run_right_choreography(picked_index)

# RIGHT choreography: side cards slide off-screen + fade, picked card flies
# to opponent body, flight.finished emits card_struck_opponent so gameplay
# can drive HIT_LOW + GUARD_DOWN.
func _run_right_choreography(picked_index: int) -> void:
	_start_exit_tween(picked_index)
	_start_picked_card_flight(picked_index, func():
		_cards[picked_index].visible = false
		# Direction.RIGHT = 1 (matches Opponent.Direction.RIGHT). Card comes
		# from the right side of the stage, so the opponent's hit-pose mirrors
		# to face right via flip_h = (direction == RIGHT).
		card_struck_opponent.emit(1)
	)
```

Note: NEUTRAL and WRONG branches deliberately route to `_run_right_choreography` for this task. Tasks 2 and 3 swap them out. This keeps the dispatch seam in place without changing player-observable behavior.

- [ ] **Step 6: Run the full carousel test suite to confirm behavior is preserved**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gexit
```
Expected: all tests pass (refactor preserves behavior — `answer_submitted` still emits at impact frame, `card_struck_opponent` still emits after flight on every outcome since all three branches still call `_run_right_choreography`).

- [ ] **Step 7: Commit**

```bash
cd /Users/nicholasmejia/godot/love-and-boxing && git add scripts/ui/answer_carousel.gd tests/unit/test_answer_carousel.gd && git commit -m "refactor(carousel): extract per-outcome dispatch in _do_punch_chain

All three outcomes still route to _run_right_choreography; behavior unchanged.
Per-outcome helpers wired in follow-up tasks. _start_picked_card_flight now
takes an on_landed Callable so each choreography can inject its post-landing
behavior (signal emit for RIGHT, rebound for NEUTRAL, never called on WRONG)."
```

---

### Task 2: NEUTRAL outcome — skip signal emit + Card Rebound on picked card

**Files:**
- Modify: `scripts/ui/answer_carousel.gd` (add `_run_neutral_choreography`, `_animate_card_rebound`, constants, member field; rewire NEUTRAL dispatch)
- Modify: `tests/unit/test_answer_carousel.gd` (add RED test for NEUTRAL no-emit)

NEUTRAL keeps the side-card exit + picked-card flight identical to RIGHT (so the card visually still touches the opponent and the flight-end `opponent_punch_body` SFX still plays). The difference is the `on_landed` callback: instead of hiding the card + emitting `card_struck_opponent`, it kicks off the Card Rebound animation, which bounces the picked card screen-right + down with a 720° clockwise spin, scale-tapers from 0.5× to 0.35×, fades alpha 1.0→0 over the trailing 150ms, and finishes off-screen over 400ms.

- [ ] **Step 1: Write the failing test for NEUTRAL no-emit**

Add to `tests/unit/test_answer_carousel.gd`, after the existing `test_card_struck_opponent_emits_after_flight_with_direction_right` (around line 307):

```gdscript
# --- Per-outcome card choreography ---

func test_neutral_outcome_does_not_emit_card_struck_opponent():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt_all(Outcome.Type.NEUTRAL))
	await get_tree().process_frame
	var emitted: Array = []
	c.card_struck_opponent.connect(func(direction): emitted.append(direction))
	_send_action("menu_confirm")
	# Wait through glove travel + flight + the full rebound window so any
	# late emit would have fired by now.
	var total = PlayerGloves.GLOVE_TRAVEL_DURATION + AnswerCarousel.CARD_FLIGHT_DURATION + AnswerCarousel.CARD_REBOUND_DURATION + 0.1
	await get_tree().create_timer(total).timeout
	assert_eq(emitted.size(), 0, "card_struck_opponent must NOT emit on NEUTRAL outcome — opponent stays IDLE through the rebound")
```

- [ ] **Step 2: Run the test to confirm it fails (RED)**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gunit_test_name=test_neutral_outcome_does_not_emit_card_struck_opponent -gexit
```
Expected: FAIL with two possible failure modes — either (a) `parser error: Identifier "CARD_REBOUND_DURATION" not found` because the constant doesn't exist yet, or (b) `card_struck_opponent must NOT emit on NEUTRAL outcome` because today the NEUTRAL branch routes to `_run_right_choreography` which emits. Either failure is the expected RED state.

- [ ] **Step 3: Add the Card Rebound constants block and member field**

In `scripts/ui/answer_carousel.gd`, append the rebound constants right after `HIT_HOLD_DURATION := 0.25` (around line 37) so all carousel tuning lives in one contiguous block:

```gdscript
# Card Rebound (NEUTRAL outcome). The picked card lands on the opponent,
# then parabolically arcs screen-right + down past the opponent and exits
# off-screen, spinning 720° clockwise. Reads as "deflected without effect."
# Plays AFTER the standard picked-card flight (same flight tween as RIGHT).
const CARD_REBOUND_DURATION := 0.40
const CARD_REBOUND_OFFSET_X := 600.0        # screen-right travel past landing
const CARD_REBOUND_APEX_Y := -120.0         # parabolic apex above landing (negative = up in Godot 2D)
const CARD_REBOUND_END_Y := 320.0           # ends below landing point (off-screen)
const CARD_REBOUND_END_SCALE := 0.35        # tapers from CARD_FLIGHT_END_SCALE (0.5)
const CARD_REBOUND_FADE_TAIL := 0.15        # alpha fades to 0 over the last 150ms only
const CARD_REBOUND_ROTATION_DEG := 720.0    # two full Z spins, clockwise
```

Then add the tween member field next to the existing `_card_flight_tween` declaration (around line 56):

```gdscript
var _card_rebound_tween: Tween = null
```

And in `display_prompt`, add a kill-on-redisplay block matching the existing pattern (after the `_card_flight_tween` kill at line 116-118):

Find this block:
```gdscript
		if _card_flight_tween:
			_card_flight_tween.kill()
			_card_flight_tween = null
		if _card_flash_tween:
			_card_flash_tween.kill()
			_card_flash_tween = null
```

Replace with:
```gdscript
		if _card_flight_tween:
			_card_flight_tween.kill()
			_card_flight_tween = null
		if _card_rebound_tween:
			_card_rebound_tween.kill()
			_card_rebound_tween = null
		if _card_flash_tween:
			_card_flash_tween.kill()
			_card_flash_tween = null
```

Also reset card rotation in `display_prompt` so a NEUTRAL → next-prompt transition doesn't leave the rebound's spin baked into the card. Add this inside the existing `for card in _cards:` loop near the top of `display_prompt` (currently sets `card.modulate.a = start_alpha`):

Find:
```gdscript
		for card in _cards:
			card.modulate.a = start_alpha
```

Replace with:
```gdscript
		for card in _cards:
			card.modulate.a = start_alpha
			card.rotation = 0.0
```

- [ ] **Step 4: Add `_animate_card_rebound` helper**

Append to `scripts/ui/answer_carousel.gd` after `_start_picked_card_flight`:

```gdscript
# Card Rebound (NEUTRAL outcome). Animates the picked card from its
# post-flight landing position into a screen-right + down parabolic arc with
# a 720° clockwise Z-rotation, scale taper, and a trailing alpha fade. Hides
# the card at the end. Caller must invoke this AFTER the picked-card flight
# tween has resolved so the start position matches the landing position.
func _animate_card_rebound(picked_index: int) -> void:
	var card := _cards[picked_index]
	if _card_rebound_tween:
		_card_rebound_tween.kill()
		_card_rebound_tween = null
	var start_pos := card.position
	var apex_y := start_pos.y + CARD_REBOUND_APEX_Y
	var end_pos := Vector2(start_pos.x + CARD_REBOUND_OFFSET_X, start_pos.y + CARD_REBOUND_END_Y)
	var half := CARD_REBOUND_DURATION * 0.5
	_card_rebound_tween = create_tween()
	_card_rebound_tween.set_parallel(true)
	# X glides linearly across the full window.
	_card_rebound_tween.tween_property(card, "position:x", end_pos.x, CARD_REBOUND_DURATION)
	# Y arcs up then down (parabolic).
	_card_rebound_tween.tween_property(card, "position:y", apex_y, half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_card_rebound_tween.tween_property(card, "position:y", end_pos.y, half) \
		.set_delay(half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Scale tapers from CARD_FLIGHT_END_SCALE (0.5, set by the flight tween)
	# to CARD_REBOUND_END_SCALE (0.35) across the full window.
	_card_rebound_tween.tween_property(card, "scale", Vector2(CARD_REBOUND_END_SCALE, CARD_REBOUND_END_SCALE), CARD_REBOUND_DURATION)
	# Alpha only fades over the trailing tail — card stays visible through
	# most of the rebound so the spin reads.
	_card_rebound_tween.tween_property(card, "modulate:a", 0.0, CARD_REBOUND_FADE_TAIL) \
		.set_delay(CARD_REBOUND_DURATION - CARD_REBOUND_FADE_TAIL)
	# Z rotation: 720° clockwise. Godot 2D positive rotation is clockwise.
	_card_rebound_tween.tween_property(card, "rotation", deg_to_rad(CARD_REBOUND_ROTATION_DEG), CARD_REBOUND_DURATION)
	_card_rebound_tween.finished.connect(func():
		card.visible = false
	)
```

- [ ] **Step 5: Add `_run_neutral_choreography` and wire the dispatch**

Append the helper to `scripts/ui/answer_carousel.gd` right after `_run_right_choreography`:

```gdscript
# NEUTRAL choreography: side cards slide off-screen + fade (same as RIGHT),
# picked card flies to opponent body (same as RIGHT, including the flight-end
# opponent_punch_body SFX), then on landing the picked card runs Card Rebound
# instead of emitting card_struck_opponent. Opponent stays in IDLE — gameplay's
# NEUTRAL branch (_on_answer_submitted) handles the reaction-typewriter wait
# and instant prompt re-display.
func _run_neutral_choreography(picked_index: int) -> void:
	_start_exit_tween(picked_index)
	_start_picked_card_flight(picked_index, func():
		_animate_card_rebound(picked_index)
	)
```

Then update the dispatch in `_do_punch_chain` — change the NEUTRAL branch from `_run_right_choreography` to `_run_neutral_choreography`:

Old:
```gdscript
		Outcome.Type.NEUTRAL:
			_run_right_choreography(picked_index)
```

New:
```gdscript
		Outcome.Type.NEUTRAL:
			_run_neutral_choreography(picked_index)
```

- [ ] **Step 6: Run the test to confirm it passes (GREEN)**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gexit
```
Expected: all tests pass — including the new NEUTRAL no-emit test, the RIGHT-emit regression, and all pre-existing tests.

- [ ] **Step 7: Manual playtest in the Godot editor**

Launch the project in the Godot editor, enter a match, and answer a riddle with the NEUTRAL outcome (Tofu's deck has predictable answers — see `data/dialogue/tofu/deck.tres` for which answer carries which outcome, or pick by reading the reaction text). Visually verify:
- Picked card flies to the opponent body the same as today.
- At landing, the card bounces screen-right + down and spins 720° as it exits off-screen over ~400ms.
- The opponent stays in IDLE — no HIT_LOW pose, no GUARD_DOWN transition. Idle Bob continues uninterrupted.
- The reaction typewriter still plays in the RiddleBox; after `NEUTRAL_READ_HOLD` the prompt re-displays as today.

- [ ] **Step 8: Commit**

```bash
cd /Users/nicholasmejia/godot/love-and-boxing && git add scripts/ui/answer_carousel.gd tests/unit/test_answer_carousel.gd && git commit -m "feat(carousel): NEUTRAL outcome runs Card Rebound, skips card_struck_opponent

Picked card lands on the opponent identically to RIGHT, then bounces
screen-right and spins 720° off-screen over 400ms. card_struck_opponent
no longer emits on NEUTRAL — opponent stays in IDLE through the rebound."
```

---

### Task 3: WRONG outcome — Card Toss replaces side-exit + picked-flight

**Files:**
- Modify: `scripts/ui/answer_carousel.gd` (add `_run_wrong_choreography`, `_animate_card_toss`, constants, member field; rewire WRONG dispatch)
- Modify: `tests/unit/test_answer_carousel.gd` (add RED test for WRONG no-emit)

WRONG drops the side-card exit tween *and* the picked-card flight entirely. All three cards instead run Card Toss in parallel: fan-out directions (left card hooks left, picked/center card jabs upward, right card hooks right), per-card jitter on apex height (~±15%) and toss duration (~±10%) so the three cards don't move identically. The picked card still flashes white at the impact frame (shared with RIGHT/NEUTRAL). No `card_struck_opponent` emit. No flight-end audio (no flight). The existing gameplay WRONG branch (opponent swings at player, heart damage, screen-flash) fires from the impact-frame `answer_submitted` emit and runs in parallel with the Card Toss — unchanged.

- [ ] **Step 1: Write the failing test for WRONG no-emit**

Add to `tests/unit/test_answer_carousel.gd`, after `test_neutral_outcome_does_not_emit_card_struck_opponent`:

```gdscript
func test_wrong_outcome_does_not_emit_card_struck_opponent():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt_all(Outcome.Type.WRONG))
	await get_tree().process_frame
	var emitted: Array = []
	c.card_struck_opponent.connect(func(direction): emitted.append(direction))
	_send_action("menu_confirm")
	# Wait through glove travel + the full Card Toss window so any late
	# emit would have fired by now.
	var total = PlayerGloves.GLOVE_TRAVEL_DURATION + AnswerCarousel.CARD_TOSS_DURATION + AnswerCarousel.CARD_TOSS_DURATION * AnswerCarousel.CARD_TOSS_DURATION_JITTER + 0.1
	await get_tree().create_timer(total).timeout
	assert_eq(emitted.size(), 0, "card_struck_opponent must NOT emit on WRONG outcome — no card flies to the opponent")
```

- [ ] **Step 2: Run the test to confirm it fails (RED)**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gunit_test_name=test_wrong_outcome_does_not_emit_card_struck_opponent -gexit
```
Expected: FAIL with `parser error: Identifier "CARD_TOSS_DURATION" not found` (constants don't exist yet) or `card_struck_opponent must NOT emit on WRONG outcome` (WRONG branch still routes through right choreography after Task 1/2).

- [ ] **Step 3: Add the Card Toss constants block and member field**

In `scripts/ui/answer_carousel.gd`, append the Card Toss constants directly below the Card Rebound block added in Task 2:

```gdscript
# Card Toss (WRONG outcome). All three cards fan outward in parallel —
# left card hooks left, picked (center) card jabs upward, right card hooks
# right. Per-card jitter on apex and duration keeps the three from moving
# identically. Replaces both the side-card exit tween and the picked-card
# flight on WRONG (neither runs on this path).
const CARD_TOSS_DURATION := 0.30
const CARD_TOSS_HOOK_PX := 480.0            # side cards' horizontal travel
const CARD_TOSS_APEX_Y := -180.0            # parabolic apex above start
const CARD_TOSS_END_Y := 240.0              # ends below start (off-stage)
const CARD_TOSS_END_SCALE := 0.5            # tapers from 1.0× (center) or 0.7× (sides)
const CARD_TOSS_ROTATION_DEG := 30.0        # tumble angle in the toss direction
const CARD_TOSS_APEX_JITTER := 0.15         # ±15% on per-card apex height
const CARD_TOSS_DURATION_JITTER := 0.10     # ±10% on per-card duration
```

Add the tween member field next to the existing `_card_rebound_tween` declaration:

```gdscript
var _card_toss_tweens: Array[Tween] = []
```

And in `display_prompt`, add a kill-on-redisplay block right after the `_card_rebound_tween` kill block added in Task 2:

Find:
```gdscript
		if _card_rebound_tween:
			_card_rebound_tween.kill()
			_card_rebound_tween = null
		if _card_flash_tween:
```

Replace with:
```gdscript
		if _card_rebound_tween:
			_card_rebound_tween.kill()
			_card_rebound_tween = null
		for t in _card_toss_tweens:
			if t and t.is_valid():
				t.kill()
		_card_toss_tweens.clear()
		if _card_flash_tween:
```

- [ ] **Step 4: Add `_animate_card_toss` helper**

Append to `scripts/ui/answer_carousel.gd` after `_animate_card_rebound`:

```gdscript
# Card Toss (WRONG outcome). Tosses a single card outward along a parabolic
# arc with a horizontal sign determined by its slot role at impact. Records
# the tween in _card_toss_tweens so display_prompt can kill it. Hides the
# card at the end. Caller iterates all three cards and dispatches per role.
func _animate_card_toss(card: AnswerCard, role: int) -> void:
	var direction: float
	match role:
		Slot.SIDE_LEFT:
			direction = -1.0
		Slot.SIDE_RIGHT:
			direction = 1.0
		_:
			direction = 0.0    # CENTER — jabs straight up
	var horiz := direction * CARD_TOSS_HOOK_PX
	var apex_scale := 1.0 + randf_range(-CARD_TOSS_APEX_JITTER, CARD_TOSS_APEX_JITTER)
	var duration_scale := 1.0 + randf_range(-CARD_TOSS_DURATION_JITTER, CARD_TOSS_DURATION_JITTER)
	var dur := CARD_TOSS_DURATION * duration_scale
	var half := dur * 0.5
	var start_pos := card.position
	var apex_y := start_pos.y + CARD_TOSS_APEX_Y * apex_scale
	var end_pos := Vector2(start_pos.x + horiz, start_pos.y + CARD_TOSS_END_Y)
	# Center card has no horizontal direction → give it a small random tumble
	# so it doesn't sit dead-still rotationally while the sides spin.
	var rotation_sign := direction if direction != 0.0 else (1.0 if randf() > 0.5 else -1.0)
	var rotation_target := deg_to_rad(CARD_TOSS_ROTATION_DEG) * rotation_sign
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position:x", end_pos.x, dur)
	tween.tween_property(card, "position:y", apex_y, half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position:y", end_pos.y, half) \
		.set_delay(half).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "scale", Vector2(CARD_TOSS_END_SCALE, CARD_TOSS_END_SCALE), dur)
	tween.tween_property(card, "modulate:a", 0.0, dur)
	tween.tween_property(card, "rotation", rotation_target, dur)
	tween.finished.connect(func():
		card.visible = false
	)
	_card_toss_tweens.append(tween)
```

- [ ] **Step 5: Add `_run_wrong_choreography` and wire the dispatch**

Append the helper to `scripts/ui/answer_carousel.gd` after `_run_neutral_choreography`:

```gdscript
# WRONG choreography: neither the side-card exit tween nor the picked-card
# flight runs. All three cards run Card Toss in parallel, fanning outward
# from their current slot roles (computed at impact via _slot_role_for).
# card_struck_opponent does NOT emit — no card lands on the opponent. The
# flight-end opponent_punch_body SFX is suppressed (no flight to end). The
# opponent's reaction is owned entirely by gameplay's existing WRONG branch
# (opponent swings at player, heart damage, screen-flash), which fires from
# the impact-frame answer_submitted emit and runs in parallel with the toss.
func _run_wrong_choreography() -> void:
	_card_toss_tweens.clear()
	for i in _cards.size():
		var role := _slot_role_for(i, _highlight_index)
		_animate_card_toss(_cards[i], role)
```

Then update the dispatch in `_do_punch_chain` — change the WRONG branch from `_run_right_choreography` to `_run_wrong_choreography`:

Old:
```gdscript
		Outcome.Type.WRONG:
			_run_right_choreography(picked_index)
```

New:
```gdscript
		Outcome.Type.WRONG:
			_run_wrong_choreography()
```

- [ ] **Step 6: Run the test to confirm it passes (GREEN)**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gexit
```
Expected: all tests pass — WRONG no-emit, NEUTRAL no-emit, RIGHT-emit regression, and all pre-existing tests.

- [ ] **Step 7: Manual playtest in the Godot editor**

Launch the project, enter a match, and answer a riddle with the WRONG outcome. Visually verify:
- All three cards (not just the picked one) fly outward at the impact frame: left card hooks left, picked card jabs upward, right card hooks right, with visible per-card variance in apex height and duration.
- The picked card still flashes white at glove impact.
- The opponent does the existing WRONG reaction: swing-pose at the player, the player takes a heart of damage, screen flashes red. The opponent does NOT additionally drop to HIT_LOW + GUARD_DOWN (today's bug is fixed).
- The reaction line (if any) types into the RiddleBox; on Tofu (empty reactions) the RiddleBox hides as today.

- [ ] **Step 8: Commit**

```bash
cd /Users/nicholasmejia/godot/love-and-boxing && git add scripts/ui/answer_carousel.gd tests/unit/test_answer_carousel.gd && git commit -m "feat(carousel): WRONG outcome runs 3-card Card Toss, skips card_struck_opponent

Replaces side-card exit + picked-card flight with parallel Card Toss on all
three cards, fanning outward (left hooks left, picked jabs up, right hooks
right) with per-card apex/duration jitter. card_struck_opponent no longer
emits on WRONG — opponent's swing-at-player + damage path (gameplay's WRONG
branch) runs unchanged from the impact-frame answer_submitted emit."
```

---

### Task 4: Document the RIGHT-only contract on the `card_struck_opponent` signal

**Files:**
- Modify: `scripts/ui/answer_carousel.gd:5-10` (signal declaration doc-comment)

The existing signal doc-comment describes the universal "card hit opponent body" behavior. Now that the signal is RIGHT-only, the comment needs to reflect that — and point future readers at CONTEXT.md's Reaction State entry, which has the full per-outcome contract.

- [ ] **Step 1: Update the `card_struck_opponent` signal doc-comment**

In `scripts/ui/answer_carousel.gd`, find:

```gdscript
signal answer_submitted(outcome: int, picked: DialogueAnswer)
# Emitted when the picked card finishes its flight tween into the opponent
# body. The argument is an Opponent.Direction value indicating the side the
# card came from (always RIGHT today — the carousel is on the right of the
# stage). Gameplay forwards to Opponent.set_action(HIT_LOW, direction) and
# queues GUARD_DOWN after HIT_HOLD_DURATION.
signal card_struck_opponent(direction: int)
```

Replace with:

```gdscript
signal answer_submitted(outcome: int, picked: DialogueAnswer)
# Emitted ONLY on the RIGHT outcome, when the picked card finishes its
# flight tween into the opponent body. NEUTRAL and WRONG handle their card
# aftermath internally to the carousel (Card Rebound and Card Toss
# respectively) and do not emit this signal — see CONTEXT.md "Reaction
# State" for the per-outcome contract. The argument is an Opponent.Direction
# value indicating the side the card came from (always RIGHT today — the
# carousel is on the right of the stage). Gameplay forwards to
# Opponent.set_action(HIT_LOW, direction) and queues GUARD_DOWN after
# HIT_HOLD_DURATION.
signal card_struck_opponent(direction: int)
```

- [ ] **Step 2: Run the test suite one final time to make sure nothing regressed**

Run:
```bash
cd /Users/nicholasmejia/godot/love-and-boxing && godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/unit/test_answer_carousel.gd -gexit
```
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
cd /Users/nicholasmejia/godot/love-and-boxing && git add scripts/ui/answer_carousel.gd && git commit -m "docs(carousel): card_struck_opponent is RIGHT-only — doc the contract

Signal no longer fires on NEUTRAL (Card Rebound) or WRONG (Card Toss).
Updated declaration comment cross-references CONTEXT.md Reaction State."
```

---

## Self-Review

**Spec coverage** — Walking the locked-design memory bullet-by-bullet:
- RIGHT unchanged → Task 1 preserves it; Task 2/3 don't touch the RIGHT branch ✅
- NEUTRAL same pre-impact + flight as RIGHT → Task 2's `_run_neutral_choreography` calls `_start_exit_tween` and `_start_picked_card_flight` identically ✅
- NEUTRAL flight-end `opponent_punch_body` SFX kept → the refactored `_start_picked_card_flight` (Task 1 Step 4) fires the SFX before `on_landed.call()`, so NEUTRAL inherits it ✅
- NEUTRAL Card Rebound (parabolic screen-right + down, 720° clockwise, scale 0.5→0.35, alpha tail fade 150ms, 400ms total, off-screen exit) → Task 2 Step 4 implements all six parameters ✅
- NEUTRAL opponent stays IDLE with bob continuing → Task 2 makes `card_struck_opponent` not emit → gameplay's `_on_card_struck_opponent` doesn't fire → no HIT_LOW, no GUARD_DOWN, no bob freeze ✅
- WRONG no side-card exit, no picked-card flight → Task 3 `_run_wrong_choreography` calls neither ✅
- WRONG 3-card Card Toss fanning outward → Task 3 Step 4 implements direction per role; Step 5 iterates all three ✅
- WRONG per-card apex jitter ±15%, duration jitter ±10% → Task 3 Step 4 uses `randf_range` on both ✅
- WRONG picked card still flashes white at impact → `_start_card_flash` stays in the shared impact-frame block in `_do_punch_chain` ✅
- WRONG no flight-end audio → no `_start_picked_card_flight` call means the `opponent_punch_body` inside it never fires ✅
- WRONG gameplay damage path unchanged → no gameplay.gd changes in the plan ✅
- `card_struck_opponent` RIGHT-only → Task 2 and 3 wire each non-RIGHT branch to a helper that doesn't emit; Task 4 documents the contract ✅
- Branch inside `_do_punch_chain` post-impact via match → Task 1 Step 5 ✅
- No new audio → audio list in Task 1 Step 4 stays exactly today's `opponent_punch_body` + `menu_option_select` + flight-end `opponent_punch_body` (RIGHT/NEUTRAL only) ✅
- No opponent.gd changes → none in the plan ✅

**Placeholder scan** — no "TBD", "implement later", "fill in details", "add appropriate error handling", "similar to Task N" without inline code, or steps that describe without showing. All code blocks are present.

**Type consistency** — `_animate_card_rebound(picked_index: int)`, `_animate_card_toss(card: AnswerCard, role: int)`, `_run_right_choreography(picked_index: int)`, `_run_neutral_choreography(picked_index: int)`, `_run_wrong_choreography()` all consistent across tasks. Constant names (`CARD_REBOUND_DURATION`, `CARD_TOSS_DURATION`, `CARD_TOSS_DURATION_JITTER`, etc.) used in tests match definitions in production code. `_start_picked_card_flight(picked_index: int, on_landed: Callable)` signature used identically in `_run_right_choreography` and `_run_neutral_choreography`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-24-carousel-outcome-card-behaviors.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
