class_name TraceBorder
extends Control

# Tuning constants — see docs/superpowers/specs/2026-05-21-prompt-trace-telegraph-design.md
const _LAP_SECONDS := 0.20
const _TAIL_FRACTION := 1.0 / 3.0
const _SEGMENT_COUNT := 24
const _LINE_THICKNESS := 5.0
const _HEAD_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const _MID_COLOR := Color(1.0, 0.15, 0.75, 1.0)
const _TAIL_COLOR := Color(0.55, 0.10, 0.85, 0.0)

# Returns the (x, y) point on the box perimeter for normalized t ∈ [0, 1).
# Clockwise from top-left: top edge → right edge → bottom edge → left edge.
# t wraps via fposmod, so negative or > 1.0 inputs map back into [0, 1).
func _perimeter_point(t: float) -> Vector2:
	var w := size.x
	var h := size.y
	var perimeter := 2.0 * (w + h)
	var u := fposmod(t, 1.0) * perimeter
	if u < w:
		return Vector2(u, 0.0)
	if u < w + h:
		return Vector2(w, u - w)
	if u < 2.0 * w + h:
		return Vector2(w - (u - w - h), h)
	return Vector2(0.0, h - (u - 2.0 * w - h))

# Returns the color for trail segment i ∈ [0, _SEGMENT_COUNT).
# i = 0 is the head, i = _SEGMENT_COUNT - 1 is the tail end.
# Linear interp head → mid (first half), then mid → tail (second half).
func _trail_color(i: int) -> Color:
	var u := float(i) / float(_SEGMENT_COUNT - 1)
	if u < 0.5:
		return _HEAD_COLOR.lerp(_MID_COLOR, u * 2.0)
	return _MID_COLOR.lerp(_TAIL_COLOR, (u - 0.5) * 2.0)
