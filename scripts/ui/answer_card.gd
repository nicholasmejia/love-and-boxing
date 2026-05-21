class_name AnswerCard
extends Control

@onready var _text: RichTextLabel = $Stack/Text
@onready var _image: TextureRect = $Stack/Image
@onready var _highlight: ColorRect = $Highlight

var _outcome: int = Outcome.Type.NEUTRAL

func display(answer: DialogueAnswer) -> void:
	_outcome = answer.outcome
	if answer.has_image():
		_image.texture = answer.image
		_image.visible = true
		_text.visible = false
	else:
		_text.text = "[center]%s[/center]" % answer.text
		_text.visible = true
		_image.visible = false

func set_highlighted(highlighted: bool) -> void:
	_highlight.visible = highlighted

func outcome() -> int:
	return _outcome
