class_name WasdPrompt
extends Control

@onready var _label: Label = $Label
@onready var _bg: ColorRect = $Background
@onready var _image: TextureRect = $Image

func show_direction(direction: int) -> void:
	var token := _token_for(direction)
	_label.text = token.to_upper()
	var path := "res://assets/sprites/ui/prompt_%s.png" % token
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_image.texture = tex
		_image.visible = true
		_label.visible = false
		_bg.visible = false
	else:
		_image.visible = false
		_label.visible = true
		_bg.visible = true
	visible = true

func hide_prompt() -> void:
	visible = false

func _token_for(direction: int) -> String:
	match direction:
		SimonSequence.Direction.HEAD: return "w"
		SimonSequence.Direction.LEFT: return "a"
		SimonSequence.Direction.BODY: return "s"
		SimonSequence.Direction.RIGHT: return "d"
	return ""
