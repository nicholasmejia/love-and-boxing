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

func get_cards() -> Array[AnswerCard]:
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
		_state = State.REACTION  # lock for the duration
		_start_exit_tween(picked_index)
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
