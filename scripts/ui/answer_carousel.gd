class_name AnswerCarousel
extends Control

signal answer_submitted(outcome: int, picked: DialogueAnswer)
# Emitted synchronously on K-press, BEFORE the GLOVE_TRAVEL_DURATION await that
# delays answer_submitted. Gameplay uses this to end the Simon phase the instant
# the player commits — otherwise the defense show loop, repeat-phase timer, and
# any in-flight breather_gap continue to run during the ~150ms glove travel,
# letting stale step_flashed emissions, timeouts, and damage events leak into
# the attack phase. answer_submitted still owns the impact-frame choreography
# (attack begin / WRONG hit / NEUTRAL re-display); answer_committed is the
# earlier "stop everything Simon-side" beat.
signal answer_committed(outcome: int)
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

enum State { NORMAL, REACTION }

# Carousel layout — container-local (the AnswerCarousel root is the origin).
# Slot anchors are Vector2 offsets from the container's logical CENTER point.
# Side slots sit on a diagonal tilt (SIDE_OFFSET.y non-zero), but the OFF-screen
# anchors are AXIS-LOCKED to each side: LEFT-side motion is purely horizontal
# (OFF_LEFT shares SIDE_LEFT's Y), RIGHT-side motion is purely vertical
# (OFF_RIGHT shares SIDE_RIGHT's X). This applies to both the wrap exit/entry
# and the picked-card exit tween. SIDE↔CENTER lerps remain diagonal.
const CONTAINER_WIDTH := 900.0
const CONTAINER_HEIGHT := 197.0
const CARD_WIDTH := 288.0
const CARD_HEIGHT := 197.0
const CENTER_X := CONTAINER_WIDTH * 0.5
const CENTER_Y := CONTAINER_HEIGHT * 0.5
const SIDE_OFFSET := Vector2(140.0, 90.0)         # X = distance to side slot, Y = diagonal tilt
const OFF_SCREEN_OFFSET := Vector2(420.0, 270.0)  # X = LEFT-side horizontal travel, Y = RIGHT-side vertical travel
const SIDE_SCALE := 0.7
const CENTER_SCALE := 1.0
const CENTER_Z := 10
const SIDE_Z := 0
const CENTER_ALPHA := 1.0
const SIDE_ALPHA := 0.65   # de-emphasizes unselected side cards at rest
# Animation timings (seconds).
const ROTATION_DURATION := 0.18
const FADE_IN_DURATION := 0.15
const EXIT_DURATION := 0.18
const CARD_FLIGHT_DURATION  := 0.20
const CARD_FLASH_DURATION   := 0.08
const CARD_FLIGHT_END_SCALE := 0.5
const HIT_HOLD_DURATION := 0.25
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
# True between display_prompt (text-body) and the body_render_complete signal
# that triggers start_fade_in. Without this, J/L during the riddle typewriter
# would invoke _apply_all_transforms and overwrite the cards' alpha=0, making
# them pop in early. Image-body prompts and display_prompt_instant skip this
# wait — they're interactable as soon as they mount.
var _is_waiting_for_render: bool = false
var _fade_tween: Tween = null
var _exit_tween: Tween = null
var _card_flight_tween: Tween = null
var _card_rebound_tween: Tween = null
var _card_toss_tweens: Array[Tween] = []
var _card_flash_tween: Tween = null
var _is_punching: bool = false
var _player_gloves: PlayerGloves = null
var _opponent_target_callback: Callable = func(): return Vector2(960, 480)  # default fallback

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

func get_cards() -> Array[AnswerCard]:
	return _cards

# Injected by gameplay.tscn wiring — the carousel needs a PlayerGloves
# reference to fire the K-confirm punch chain. If null (e.g., tests that
# don't need the punch behavior), K still emits answer_submitted but no
# glove animation plays.
func set_player_gloves(gloves: PlayerGloves) -> void:
	_player_gloves = gloves

# Injected by gameplay wiring — supplies the opponent body's global position
# for the picked-card flight target. Default is a center-of-stage fallback
# for tests that don't wire a real opponent.
func set_opponent_target_callback(cb: Callable) -> void:
	_opponent_target_callback = cb

# True from K-press through the per-outcome choreography until the next prompt
# loads (display_prompt resets it). Gameplay reads this so phase-transition
# code can avoid hiding the carousel container mid-choreography — the cards
# self-hide via tween-finished callbacks; killing the container would cancel
# the visible animation.
func is_punching() -> bool:
	return _is_punching

# Stages the cards for a new prompt. _apply_all_transforms below sets each
# card's rest-state alpha per slot role (CENTER_ALPHA, SIDE_ALPHA). Text-body
# prompts override that to 0 — start_fade_in animates each card back up to
# its per-slot target after the body typewriter completes.
func display_prompt(prompt: DialoguePrompt) -> void:
	_state = State.NORMAL
	visible = true
	for card in _cards:
		card.visible = true
		card.rotation = 0.0
	_is_fading_in = false
	_is_punching = false
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	if _exit_tween:
		_exit_tween.kill()
		_exit_tween = null
	if _card_flight_tween:
		_card_flight_tween.kill()
		_card_flight_tween = null
	if _card_rebound_tween:
		_card_rebound_tween.kill()
		_card_rebound_tween = null
	for t in _card_toss_tweens:
		if t and t.is_valid():
			t.kill()
	_card_toss_tweens.clear()
	if _card_flash_tween:
		_card_flash_tween.kill()
		_card_flash_tween = null
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
	# Text-body prompts hide cards until the body typewriter completes.
	# start_fade_in animates each card up to its per-slot alpha target.
	# _is_waiting_for_render gates input until that fade-in trigger fires so
	# J/L during the typewriter can't repaint card alpha via _apply_all_transforms.
	if not prompt.has_image_body():
		for card in _cards:
			card.modulate.a = 0.0
		_is_waiting_for_render = true
	else:
		_is_waiting_for_render = false

# Synchronous variant — used by the NEUTRAL re-display path. Skips the fade
# regardless of prompt type (player has already read the prompt once).
func display_prompt_instant(prompt: DialoguePrompt) -> void:
	display_prompt(prompt)
	# Instant path (NEUTRAL re-display) skips the typewriter — clear the
	# render gate so input opens immediately on the next frame.
	_is_waiting_for_render = false
	_apply_all_transforms()

# Awaitable. Public so the caller (gameplay) can trigger the fade once
# RiddleBox.body_render_complete fires. Image-body prompts skip this.
func start_fade_in() -> void:
	if _state != State.NORMAL:
		return
	_is_waiting_for_render = false
	_is_fading_in = true
	if _fade_tween:
		_fade_tween.kill()
		_fade_tween = null
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	for i in _cards.size():
		var role := _slot_role_for(i, _highlight_index)
		_fade_tween.tween_property(_cards[i], "modulate:a", _slot_alpha(role), FADE_IN_DURATION)
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
		var target_anchor: Vector2
		if role == Slot.SIDE_LEFT:
			target_anchor = _slot_anchor(Slot.OFF_LEFT)
		else:
			target_anchor = _slot_anchor(Slot.OFF_RIGHT)
		var target_position := _make_position(target_anchor)
		_exit_tween.tween_property(card, "position", target_position, EXIT_DURATION)
		_exit_tween.tween_property(card, "modulate:a", 0.0, EXIT_DURATION)
	_exit_tween.finished.connect(func():
		for i in _cards.size():
			if i != picked_index:
				_cards[i].visible = false
	)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if _state == State.REACTION:
		return
	# Lock all carousel input while the cards are still arriving (fade-in),
	# while the riddle typewriter is mid-render (cards alpha=0; J/L would
	# repaint them via _apply_all_transforms), OR while the K-confirm punch
	# chain is in flight.
	if _is_fading_in or _is_punching or _is_waiting_for_render:
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
		_state = State.REACTION
		_is_punching = true
		# Fire answer_committed BEFORE _do_punch_chain so gameplay can tear down
		# the Simon phase synchronously on K-press. answer_submitted still emits
		# from inside _do_punch_chain at the impact frame for outcome-specific
		# choreography.
		answer_committed.emit(_picked_answers[picked_index].outcome)
		# Phase 3 Task 10: glove launches NOW; impact-frame work fires
		# after GLOVE_TRAVEL_DURATION via the await in _do_punch_chain.
		_do_punch_chain(picked_index)

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
		_cards[i].modulate.a = t.alpha

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
	var alpha_val: float = lerp(_slot_alpha(from_role), _slot_alpha(to_role), progress)
	var z_val := _slot_z(to_role)

	return {
		"position": _make_position(anchor),
		"scale": Vector2(scale_val, scale_val),
		"z": z_val,
		"alpha": alpha_val,
	}

# Converts a slot anchor (Vector2 center point in container-local space) into
# the card's top-left position. Pivot is at the card's geometric center (set
# in _ready), so this lands the visual center on the anchor. All position
# math MUST route through this — ADR-0001.
func _make_position(anchor: Vector2) -> Vector2:
	return Vector2(anchor.x - CARD_WIDTH / 2.0, anchor.y - CARD_HEIGHT / 2.0)

func _slot_role_for(card_index: int, center_index: int) -> int:
	var relative := (card_index - center_index + 3) % 3
	match relative:
		0: return Slot.CENTER
		1: return Slot.SIDE_RIGHT
		_: return Slot.SIDE_LEFT  # relative == 2

func _slot_anchor(slot: int) -> Vector2:
	match slot:
		# OFF_LEFT shares SIDE_LEFT's Y → wrap exit/entry along the LEFT-side horizontal axis.
		Slot.OFF_LEFT:   return Vector2(CENTER_X - OFF_SCREEN_OFFSET.x,  CENTER_Y + SIDE_OFFSET.y)
		Slot.SIDE_LEFT:  return Vector2(CENTER_X - SIDE_OFFSET.x,        CENTER_Y + SIDE_OFFSET.y)
		Slot.CENTER:     return Vector2(CENTER_X,                         CENTER_Y)
		Slot.SIDE_RIGHT: return Vector2(CENTER_X + SIDE_OFFSET.x,        CENTER_Y - SIDE_OFFSET.y)
		# OFF_RIGHT shares SIDE_RIGHT's X → wrap exit/entry along the RIGHT-side vertical axis.
		Slot.OFF_RIGHT:  return Vector2(CENTER_X + SIDE_OFFSET.x,        CENTER_Y - OFF_SCREEN_OFFSET.y)
		_:               return Vector2(CENTER_X,                         CENTER_Y)

func _slot_scale(slot: int) -> float:
	if slot == Slot.CENTER:
		return CENTER_SCALE
	return SIDE_SCALE

func _slot_z(slot: int) -> int:
	if slot == Slot.CENTER:
		return CENTER_Z
	return SIDE_Z

func _slot_alpha(slot: int) -> float:
	if slot == Slot.CENTER:
		return CENTER_ALPHA
	return SIDE_ALPHA

func _trigger_glove_punch(picked_index: int) -> void:
	AudioBus.play_sfx("swing")
	if _player_gloves == null:
		return
	var card := _cards[picked_index]
	# Card's global_position points to its top-left; offset to its visual center.
	var card_center := card.global_position + Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * card.scale
	_player_gloves.punch_at_screen_position(card_center)

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
			_run_neutral_choreography(picked_index)
		Outcome.Type.WRONG:
			_run_wrong_choreography()

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
	# Y arcs up then down (parabolic). The two Y tweeners share the property —
	# delay on the second must equal the first's duration so they never race
	# on the same frame. Both equal `half` here; keep them in sync if tuning.
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
	# Y arcs up then down (parabolic). The two Y tweeners share the property —
	# delay on the second must equal the first's duration so they never race
	# on the same frame. Both equal `half` here; keep them in sync if tuning.
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
