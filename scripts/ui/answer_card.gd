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
