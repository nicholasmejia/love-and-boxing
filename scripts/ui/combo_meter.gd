class_name ComboMeter
extends Control

const COMBO_PATHS := {
	1: "res://assets/sprites/ui/combo_x1.png",
	2: "res://assets/sprites/ui/combo_x2.png",
	3: "res://assets/sprites/ui/combo_x3.png",
}

@onready var _texture_rect: TextureRect = $Texture
@onready var _label: Label = $Label

func _ready() -> void:
	set_level(1)

func set_level(level: int) -> void:
	var path: String = COMBO_PATHS.get(level, "")
	if path != "" and ResourceLoader.exists(path):
		_texture_rect.texture = load(path)
		_texture_rect.visible = true
		_label.visible = false
	else:
		_label.text = "x%d" % level
		_label.visible = true
		_texture_rect.visible = false
