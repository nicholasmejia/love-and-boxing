class_name HeartRow
extends HBoxContainer

const MAX_HEARTS := 5
const HEART_SIZE := 96
const FULL_PATH := "res://assets/sprites/ui/heart_full.png"
const EMPTY_PATH := "res://assets/sprites/ui/heart_empty.png"

# Loss animation tuning — heart falls, tips over, then fades out.
const LOSS_FALL_DISTANCE := 180.0
const LOSS_DURATION := 0.7
const LOSS_ROTATION := 0.75 * TAU
const LOSS_ROTATION_DELAY := 0.1
const LOSS_FADE_DELAY := 0.2

var _slots: Array[Control] = []
var _full_overlays: Array[TextureRect] = []
var _full_texture: Texture2D
var _empty_texture: Texture2D
var _previous_count: int = MAX_HEARTS

func _ready() -> void:
	_full_texture = _load_or_placeholder(FULL_PATH, Color(1, 0.2, 0.3))
	_empty_texture = _load_or_placeholder(EMPTY_PATH, Color(0.2, 0.2, 0.2))
	_slots.clear()
	_full_overlays.clear()
	for i in MAX_HEARTS:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(HEART_SIZE, HEART_SIZE)
		add_child(slot)

		var empty := TextureRect.new()
		empty.texture = _empty_texture
		empty.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		slot.add_child(empty)

		var full := TextureRect.new()
		full.texture = _full_texture
		full.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		full.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Pivot at slot center so rotation tips around the heart's middle.
		full.pivot_offset = Vector2(HEART_SIZE, HEART_SIZE) / 2.0
		slot.add_child(full)

		_slots.append(slot)
		_full_overlays.append(full)
	set_hearts(MAX_HEARTS)

func set_hearts(count: int) -> void:
	count = clampi(count, 0, MAX_HEARTS)
	for i in _full_overlays.size():
		var was_full := i < _previous_count
		var is_full := i < count
		if was_full and not is_full:
			_animate_loss(i)
		elif not was_full and is_full:
			_reset_full(i)
	_previous_count = count

func _animate_loss(index: int) -> void:
	var full := _full_overlays[index]
	full.position = Vector2.ZERO
	full.rotation = 0.0
	full.modulate.a = 1.0
	full.visible = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(full, "position:y", LOSS_FALL_DISTANCE, LOSS_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(full, "rotation", LOSS_ROTATION, LOSS_DURATION - LOSS_ROTATION_DELAY) \
		.set_delay(LOSS_ROTATION_DELAY)
	tween.tween_property(full, "modulate:a", 0.0, LOSS_DURATION - LOSS_FADE_DELAY) \
		.set_delay(LOSS_FADE_DELAY).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func(): full.visible = false)

func _reset_full(index: int) -> void:
	var full := _full_overlays[index]
	full.position = Vector2.ZERO
	full.rotation = 0.0
	full.modulate.a = 1.0
	full.visible = true

func _load_or_placeholder(path: String, color: Color) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.create(HEART_SIZE, HEART_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)
