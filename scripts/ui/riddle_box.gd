class_name RiddleBox
extends Control

signal answer_submitted(outcome: int)

@onready var _body_text: RichTextLabel = $Layout/Body/Text
@onready var _body_image: TextureRect = $Layout/Body/Image
@onready var _cards: Array[AnswerCard] = [
	$Layout/Answers/Left,
	$Layout/Answers/Middle,
	$Layout/Answers/Right,
]

var _highlight_index: int = 1  # I = middle by default
var _typewriter_speed: float = 30.0
var _typewriter_generation: int = 0

func display(prompt: DialoguePrompt) -> void:
	if prompt.has_image_body():
		_body_image.texture = prompt.body_image
		_body_image.visible = true
		_body_text.visible = false
	else:
		_body_text.visible = true
		_body_image.visible = false
		_start_typewriter(prompt.body_text)
	for i in _cards.size():
		if i < prompt.answers.size():
			_cards[i].display(prompt.answers[i])
	_highlight_index = 1
	_refresh_highlight()

func _start_typewriter(text: String) -> void:
	_typewriter_generation += 1
	var my_generation := _typewriter_generation
	_body_text.text = text
	_body_text.visible_characters = 0
	var total := text.length()
	while _body_text.visible_characters < total:
		if my_generation != _typewriter_generation:
			return
		_body_text.visible_characters += 1
		AudioBus.play_sfx("babble")
		await get_tree().create_timer(1.0 / _typewriter_speed).timeout

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left"):
		_highlight_index = 0
		_refresh_highlight()
	elif event.is_action_pressed("menu_up"):
		_highlight_index = 1
		_refresh_highlight()
	elif event.is_action_pressed("menu_right"):
		_highlight_index = 2
		_refresh_highlight()
	elif event.is_action_pressed("menu_confirm"):
		answer_submitted.emit(_cards[_highlight_index].outcome())

func _refresh_highlight() -> void:
	for i in _cards.size():
		_cards[i].set_highlighted(i == _highlight_index)
