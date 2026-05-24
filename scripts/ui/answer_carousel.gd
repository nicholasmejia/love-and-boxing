class_name AnswerCarousel
extends Control

signal answer_submitted(outcome: int, picked: DialogueAnswer)
# Emitted when the picked card finishes its flight tween into the opponent
# body. The argument is an Opponent.Direction value indicating the side the
# card came from (always RIGHT today — the carousel is on the right of the
# stage). Gameplay forwards to Opponent.set_action(HIT_LOW, direction) and
# queues GUARD_DOWN after HIT_HOLD_DURATION.
signal card_struck_opponent(direction: int)

enum State { NORMAL, REACTION }

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
const SIDE_OFFSET := Vector2(140.0, 90.0)         # X = distance to side slot, Y = vertical tilt
const OFF_SCREEN_OFFSET := Vector2(420.0, 270.0)  # X = distance to wrap exit, Y = vertical tilt
const SIDE_SCALE := 0.7
const CENTER_SCALE := 1.0
const CENTER_Z := 10
const SIDE_Z := 0
# Animation timings (seconds).
const ROTATION_DURATION := 0.18
const FADE_IN_DURATION := 0.15
const EXIT_DURATION := 0.18
const CARD_FLIGHT_DURATION  := 0.20
const CARD_FLASH_DURATION   := 0.08
const CARD_FLIGHT_END_SCALE := 0.5
const HIT_HOLD_DURATION := 0.25

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
var _card_flight_tween: Tween = null
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

# Synchronous variant — used by the NEUTRAL re-display path. Skips the fade
# regardless of prompt type (player has already read the prompt once).
func display_prompt_instant(prompt: DialoguePrompt) -> void:
	display_prompt(prompt)
	for card in _cards:
		card.modulate.a = 1.0

# Awaitable. Public so the caller (gameplay) can trigger the fade once
# RiddleBox.body_render_complete fires. Image-body prompts skip this.
func start_fade_in() -> void:
	if _state != State.NORMAL:
		return
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
	# Lock all carousel input while the cards are still arriving (fade-in)
	# OR while the K-confirm punch chain is in flight.
	if _is_fading_in or _is_punching:
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
		Slot.OFF_LEFT:   return Vector2(CENTER_X - OFF_SCREEN_OFFSET.x,  CENTER_Y + OFF_SCREEN_OFFSET.y)
		Slot.SIDE_LEFT:  return Vector2(CENTER_X - SIDE_OFFSET.x,        CENTER_Y + SIDE_OFFSET.y)
		Slot.CENTER:     return Vector2(CENTER_X,                         CENTER_Y)
		Slot.SIDE_RIGHT: return Vector2(CENTER_X + SIDE_OFFSET.x,        CENTER_Y - SIDE_OFFSET.y)
		Slot.OFF_RIGHT:  return Vector2(CENTER_X + OFF_SCREEN_OFFSET.x,  CENTER_Y - OFF_SCREEN_OFFSET.y)
		_:               return Vector2(CENTER_X,                         CENTER_Y)

func _slot_scale(slot: int) -> float:
	if slot == Slot.CENTER:
		return CENTER_SCALE
	return SIDE_SCALE

func _slot_z(slot: int) -> int:
	if slot == Slot.CENTER:
		return CENTER_Z
	return SIDE_Z

func _trigger_glove_punch(picked_index: int) -> void:
	AudioBus.play_sfx("swing")
	if _player_gloves == null:
		return
	var card := _cards[picked_index]
	# Card's global_position points to its top-left; offset to its visual center.
	var card_center := card.global_position + Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5) * card.scale
	_player_gloves.punch_at_screen_position(card_center)

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
