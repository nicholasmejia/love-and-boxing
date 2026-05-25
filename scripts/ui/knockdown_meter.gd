class_name KnockdownMeter
extends Control

const ICON_PATH := "res://assets/sprites/ui/knockdown_icon.png"

const _PULSE_PEAK := Vector2(1.25, 1.25)
const _PULSE_UP_DURATION := 0.12
const _PULSE_DOWN_DURATION := 0.18

@onready var _icon: TextureRect = $HBox/Icon
@onready var _label: Label = $HBox/Label

var _previous_count: int = 0
var _pulse_tween: Tween

func _ready() -> void:
	if ResourceLoader.exists(ICON_PATH):
		_icon.texture = load(ICON_PATH)
		_icon.visible = true
	else:
		_icon.visible = false
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	set_count(0)

func _on_resized() -> void:
	pivot_offset = size * 0.5

func set_count(count: int) -> void:
	var increased := count > _previous_count
	_label.text = "× %d" % count
	_previous_count = count
	if increased:
		_pulse()
		AudioBus.play_sfx("knockdown_increase")

# Global-space center of the icon; the announcement banner uses this as its
# fly-to target so the knockdown tick visibly "lands" on the icon.
func icon_global_center() -> Vector2:
	return _icon.global_position + _icon.size * 0.5

func _pulse() -> void:
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	scale = Vector2.ONE
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", _PULSE_PEAK, _PULSE_UP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, _PULSE_DOWN_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
