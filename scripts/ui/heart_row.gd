class_name HeartRow
extends HBoxContainer

const MAX_HEARTS := 5
const FULL_PATH := "res://assets/sprites/ui/heart_full.png"
const EMPTY_PATH := "res://assets/sprites/ui/heart_empty.png"

@onready var _slots: Array[TextureRect] = []
var _full_texture: Texture2D
var _empty_texture: Texture2D

func _ready() -> void:
	_full_texture = _load_or_placeholder(FULL_PATH, Color(1, 0.2, 0.3))
	_empty_texture = _load_or_placeholder(EMPTY_PATH, Color(0.2, 0.2, 0.2))
	_slots.clear()
	for i in MAX_HEARTS:
		var t := TextureRect.new()
		t.custom_minimum_size = Vector2(96, 96)
		t.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		add_child(t)
		_slots.append(t)
	set_hearts(MAX_HEARTS)

func set_hearts(count: int) -> void:
	for i in _slots.size():
		_slots[i].texture = _full_texture if i < count else _empty_texture

func _load_or_placeholder(path: String, color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
