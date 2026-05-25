class_name ComboMeter
extends Control

const COMBO_PATHS := {
	1: "res://assets/sprites/ui/combo_x1.png",
	2: "res://assets/sprites/ui/combo_x2.png",
	3: "res://assets/sprites/ui/combo_x3.png",
}

const _BASE_SCALE := {
	1: Vector2(1.0, 1.0),
	2: Vector2(1.18, 1.18),
	3: Vector2(1.38, 1.38),
}

const _PULSE_PERIOD := {
	1: 1.6,
	2: 0.75,
	3: 0.38,
}

const _PULSE_AMPLITUDE := 0.06
const _SETTLE_DURATION := 0.18

@onready var _texture_rect: TextureRect = $Texture
@onready var _label: Label = $Label

var _current_level: int = 0
var _settle_tween: Tween
var _pulse_tween: Tween

func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	set_level(1)

func _on_resized() -> void:
	pivot_offset = size * 0.5

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

	if level == _current_level:
		return
	_current_level = level
	_restart_animations()

func _restart_animations() -> void:
	if _settle_tween and _settle_tween.is_valid():
		_settle_tween.kill()
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()

	var base_scale: Vector2 = _BASE_SCALE.get(_current_level, Vector2.ONE)
	var period: float = _PULSE_PERIOD.get(_current_level, 1.6)

	_settle_tween = create_tween()
	_settle_tween.tween_property(self, "scale", base_scale, _SETTLE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_settle_tween.finished.connect(_start_pulse.bind(base_scale, period))

func _start_pulse(base_scale: Vector2, period: float) -> void:
	var max_scale: Vector2 = base_scale * (1.0 + _PULSE_AMPLITUDE)
	var min_scale: Vector2 = base_scale * (1.0 - _PULSE_AMPLITUDE)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", max_scale, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", min_scale, period * 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
