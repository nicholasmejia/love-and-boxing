class_name KnockdownMeter
extends Control

const ICON_PATH := "res://assets/sprites/ui/knockdown_icon.png"

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

func _ready() -> void:
	if ResourceLoader.exists(ICON_PATH):
		_icon.texture = load(ICON_PATH)
		_icon.visible = true
	else:
		_icon.visible = false
	set_count(0)

func set_count(count: int) -> void:
	_label.text = "× %d" % count
