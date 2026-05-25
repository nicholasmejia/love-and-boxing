extends Control

const _FADE_IN_DURATION := 0.5
const _HOLD_DURATION := 2.0
const _FADE_OUT_DURATION := 0.4

@onready var _logo: TextureRect = $Logo

var _hold_timer: SceneTreeTimer
var _active_tween: Tween
var _fading_out: bool = false

func _ready() -> void:
	_logo.modulate.a = 0.0
	_run_sequence()

func _run_sequence() -> void:
	_active_tween = create_tween()
	_active_tween.tween_property(_logo, "modulate:a", 1.0, _FADE_IN_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	if _fading_out:
		return
	_hold_timer = get_tree().create_timer(_HOLD_DURATION)
	await _hold_timer.timeout
	if _fading_out:
		return
	_start_fade_out()

func _unhandled_input(event: InputEvent) -> void:
	if _fading_out:
		return
	if event.is_action_pressed("menu_confirm"):
		_start_fade_out()

func _start_fade_out() -> void:
	_fading_out = true
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween()
	_active_tween.tween_property(_logo, "modulate:a", 0.0, _FADE_OUT_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_active_tween.tween_callback(SceneRouter.goto_attract_sequence)
