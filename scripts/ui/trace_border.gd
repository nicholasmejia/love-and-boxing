class_name TraceBorder
extends Control

# Tuning constants — see docs/superpowers/specs/2026-05-21-prompt-trace-telegraph-design.md
const _LAP_SECONDS := 0.20
const _TAIL_FRACTION := 1.0 / 3.0
const _SEGMENT_COUNT := 24
const _LINE_THICKNESS := 12.0
const _HEAD_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const _MID_COLOR := Color(1.0, 0.15, 0.75, 1.0)
const _TAIL_COLOR := Color(0.55, 0.10, 0.85, 0.0)

# Returns the (x, y) point on a circle circumscribed around the box for
# normalized t ∈ [0, 1). Circle is centered on the box, radius = box_diagonal/2
# so the trace touches the bounding-box corners and floats just outside at the
# cardinal directions — reads as a halo around starburst-shaped sprites whose
# spikes reach the corners. t=0 starts at 12 o'clock, advances clockwise.
# t wraps via fposmod, so negative or > 1.0 inputs map back into [0, 1).
func _circle_point(t: float) -> Vector2:
	var center := size * 0.5
	var radius := size.length() * 0.5
	var angle := fposmod(t, 1.0) * TAU - PI * 0.5
	return center + Vector2(cos(angle), sin(angle)) * radius

# Returns the color for trail segment i ∈ [0, _SEGMENT_COUNT).
# i = 0 is the head, i = _SEGMENT_COUNT - 1 is the tail end.
# Linear interp head → mid (first half), then mid → tail (second half).
func _trail_color(i: int) -> Color:
	var u := float(i) / float(_SEGMENT_COUNT - 1)
	if u < 0.5:
		return _HEAD_COLOR.lerp(_MID_COLOR, u * 2.0)
	return _MID_COLOR.lerp(_TAIL_COLOR, (u - 0.5) * 2.0)

var _active: bool = false
var _progress: float = 0.0

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func play_trace() -> void:
	_progress = 0.0
	_active = true
	queue_redraw()

func stop_trace() -> void:
	_active = false
	queue_redraw()

func _process(delta: float) -> void:
	if not _active:
		return
	_advance(delta)
	queue_redraw()

# Pure state-machine step extracted from _process so unit tests can drive
# progress without depending on the SceneTree.
func _advance(delta: float) -> void:
	if not _active:
		return
	_progress += delta / _LAP_SECONDS
	if _progress >= 1.0:
		_progress = 1.0
		_active = false

# Draws _SEGMENT_COUNT short chord segments behind the head along the circle,
# each spanning (_TAIL_FRACTION / _SEGMENT_COUNT) of the lap. Color is sampled
# per segment so the head reads as opaque white and the tail end as transparent
# violet.
func _draw() -> void:
	if not _active:
		return
	var seg_span := _TAIL_FRACTION / float(_SEGMENT_COUNT)
	for i in _SEGMENT_COUNT:
		var t_start := _progress - float(i) * seg_span
		var t_end := _progress - float(i + 1) * seg_span
		var a := _circle_point(t_start)
		var b := _circle_point(t_end)
		draw_line(a, b, _trail_color(i), _LINE_THICKNESS)
