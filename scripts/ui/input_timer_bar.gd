class_name InputTimerBar
extends Control

# Visual countdown for the per-input window during defense repeat (and later,
# attack input). Fill bar starts full-width green and shrinks symmetrically
# inward while lerping toward red. Reset on each new input window.

@export var max_fill_width: float = 340.0
@onready var _fill: ColorRect = $Fill

const _COLOR_FULL := Color(0.3, 0.85, 0.35, 1.0)
const _COLOR_EMPTY := Color(0.9, 0.25, 0.25, 1.0)

var _duration: float = 0.0
var _elapsed: float = 0.0
var _running: bool = false

func _ready() -> void:
	visible = false
	set_process(false)

func start(duration_seconds: float) -> void:
	_duration = max(duration_seconds, 0.0001)
	_elapsed = 0.0
	_running = true
	visible = true
	set_process(true)
	_update_fill()

func cancel() -> void:
	_running = false
	visible = false
	set_process(false)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _duration:
		cancel()
		return
	_update_fill()

func _update_fill() -> void:
	var t: float = clamp(_elapsed / _duration, 0.0, 1.0)
	var half: float = max_fill_width * (1.0 - t) * 0.5
	_fill.offset_left = -half
	_fill.offset_right = half
	_fill.color = _COLOR_FULL.lerp(_COLOR_EMPTY, t)
