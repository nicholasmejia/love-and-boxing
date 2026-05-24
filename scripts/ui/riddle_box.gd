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
# Animation timings (seconds). Manually playtested per the project's
# "user is the test harness for visual/feel work" convention.
const ROTATION_DURATION := 0.18
const FADE_IN_DURATION := 0.15
const EXIT_DURATION := 0.18

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
# Rotation animation state. _is_rotating gates K-confirm; _queued_rotation
# buffers exactly one pending J/L press (delta = -1 or +1, 0 means empty).
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

func is_rendering() -> bool:
	return _is_rendering

# Awaitable. Resolves when the body typewriter AND the answer-card fade-in
# complete. Image-body prompts have no typewriter and no fade — display()
# returns immediately. Caller is the gate that controls when DefensePhase
# activates — see Riddle Render Gate in CONTEXT.md.
func display(prompt: DialoguePrompt) -> void:
	_setup_display(prompt)
	if prompt.has_image_body():
		return
	await _start_typewriter(prompt.body_text)
	await _start_fade_in()

# Synchronous full-text display. Used by the NEUTRAL re-display path where the
# player has already read this prompt — typewriter would be busywork.
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
	# Text-body prompts start the cards transparent — they fade in after the
	# typewriter completes. Image-body prompts skip the fade (no typewriter).
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

# Awaitable. Resolves when the reaction typewriter completes (or immediately
# for empty-reaction prompts, which hide the box).
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
		# A card whose visual is left-of-center exits LEFT; right-of-center
		# exits RIGHT. The picked card is at CENTER (by definition — its
		# slot role is computed relative to picked_index), so the unpicked
		# cards are guaranteed to be SIDE_LEFT or SIDE_RIGHT.
		var role := _slot_role_for(i, picked_index)
		var target_anchor_x: float
		if role == Slot.SIDE_LEFT:
			target_anchor_x = _slot_anchor_x(Slot.OFF_LEFT)
		else:
			target_anchor_x = _slot_anchor_x(Slot.OFF_RIGHT)
		var target_position := _make_position(target_anchor_x)
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

func _start_typewriter(text: String) -> void:
	_typewriter_generation += 1
	var my_generation := _typewriter_generation
	_is_rendering = true
	# Wrap in [center] so each line auto-centers horizontally. visible_characters
	# counts displayed glyphs (BBCode tags excluded), so use
	# get_total_character_count() instead of source-string length — otherwise the
	# loop would over-shoot the cap and spin forever.
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

func _start_fade_in() -> void:
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

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.REACTION:
		return
	# Lock all carousel input while the cards are still arriving (typewriter
	# running OR fade-in tween in flight). Per CONTEXT.md Riddle Render Gate,
	# the player cannot navigate or confirm an unsettled carousel.
	if _is_rendering or _is_fading_in:
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
		if _is_rotating:
			return
		var picked_index := _highlight_index
		# Order matters: show_reaction() must start the reaction typewriter
		# (flipping _is_rendering true, _state to REACTION) BEFORE emit so
		# the gameplay handler can read those flags / await reaction render.
		show_reaction(picked_index)
		answer_submitted.emit(_cards[picked_index].outcome())

func _cycle_highlight(delta: int) -> void:
	if _is_rotating:
		if _queued_rotation != 0:
			# Queue is already full (depth 1). Drop this press silently.
			return
		# Queue depth 1: buffer this press for when the in-flight tween ends.
		# Advance _highlight_index now so it always reflects the final target.
		# Audio fires at input time so queued double-taps are audibly confirmed
		# (per the carousel design — see CONTEXT.md Answer Carousel).
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

	# Scale lerps from raw progress, not the piecewise-remapped anchor_x above.
	# For wrap cards both from_role and to_role are SIDE slots (same scale), so
	# this stays flat — correct. If easing is ever added to progress, revisit:
	# the position would ease while scale would too, but the piecewise split at
	# 0.5 in the anchor_x branch could expose a midpoint discontinuity.
	var scale_val: float = lerp(_slot_scale(from_role), _slot_scale(to_role), progress)
	# Z is discrete: snap to the to-arrangement's z from frame 1. The new
	# center card rises immediately; the old center drops immediately. Visual
	# correctness comes from scale, not z, during the tween.
	var z_val := _slot_z(to_role)

	# Position formula routed through _make_position per ADR-0001.
	return {
		"position": _make_position(anchor_x),
		"scale": Vector2(scale_val, scale_val),
		"z": z_val,
	}

# Converts a carousel anchor-X (the visual center of the slot in container-local
# space) into the AnswerCard's top-left position. Pivot is set at the card's
# geometric center in _ready(), so positioning the top-left at (anchor_x -
# CARD_WIDTH/2, CENTER_Y - CARD_HEIGHT/2) lands the visual center on
# (anchor_x, CENTER_Y). Both _compute_card_transform and _start_exit_tween
# MUST route through this — see ADR-0001.
func _make_position(anchor_x: float) -> Vector2:
	return Vector2(anchor_x - CARD_WIDTH / 2.0, CENTER_Y - CARD_HEIGHT / 2.0)

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
