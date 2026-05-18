class_name MatchTimerView
extends Control

const BG_PATH := "res://assets/sprites/ui/timer_bg.png"

@onready var _bg: TextureRect = $Background
@onready var _label: Label = $Label

func _ready() -> void:
	if ResourceLoader.exists(BG_PATH):
		_bg.texture = load(BG_PATH)
		_bg.visible = true
	else:
		_bg.visible = false
	set_seconds(300.0)

func set_seconds(seconds: float) -> void:
	var s := int(ceil(seconds))
	var m := s / 60
	var r := s % 60
	_label.text = "%d:%02d" % [m, r]
