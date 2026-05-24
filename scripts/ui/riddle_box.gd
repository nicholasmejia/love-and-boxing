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
