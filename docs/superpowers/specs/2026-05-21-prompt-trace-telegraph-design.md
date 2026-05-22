# Prompt Trace Telegraph

**Date:** 2026-05-21
**Branch:** `feature/prompt-trace-telegraph` (off `main`)
**Scope:** Add a one-shot chase-light border trace to the WASD prompt's PROMPT-variant entry animation, to make incoming-attack telegraphing more visible. Success and failure variants are untouched.

## Summary

When a `WasdPrompt` enters its `Variant.PROMPT` state — both for the defense show phase (opponent demonstrating an incoming attack) and the attack show phase (sequence the player must memorize) — a bright chase-light "head" traces a single lap around the box's perimeter, with a short gradient tail fading behind it. The trace fires concurrently with the existing pulse-in scale tween and finishes well before the prompt's hold/fade-out.

The other four variants (`SUCCESS`, `FAIL`, `SUCCESS_ATTACK`, `FAIL_ATTACK`) skip the trace entirely. Their animations (`_animate_block_shake`, `_animate_hit_toss`, `_animate_damage_double_pulse`, `_animate_miss_double_pulse`) remain unchanged.

## Mechanic: Chase-Light Trace

### Visual

- A single bright "head" point travels the rectangular perimeter of the prompt box.
- Direction: clockwise, starting at the top-left corner.
- One full lap, then the trace clears. No persistent border remains.
- A trail of ~24 short segments follows the head, spanning ~1/3 of the perimeter length behind it.
- Color gradient along the trail:
  - **Head (segment 0):** white, fully opaque — `Color(1.0, 1.0, 1.0, 1.0)`
  - **Mid-trail (~50% along):** magenta — `Color(1.0, 0.15, 0.75, 1.0)`
  - **Tail end (segment 23):** violet, fully transparent — `Color(0.55, 0.10, 0.85, 0.0)`
  - Intermediate segments interpolate linearly along both color channels and alpha.
- Line thickness: 5 px (proportional to the new 188 px box; scales with `size` at runtime if the box is ever re-sized).

### Timing

- Lap duration: **0.20 seconds.**
- Fires at t=0 of `_animate_prompt_pulse`, concurrent with the scale-overshoot.
- Sebastian's tight 0.35 s show window accommodates this: 0.12 s pulse-in overlaps the first 0.12 s of the trace; the remaining 0.08 s of the trace overlaps the hold; 0.07 s of slack remains before the 0.08 s fade-out begins. Tofu's 0.8 s show window is far more relaxed.

### Lifecycle

- Triggered exclusively by `WasdPrompt._animate_prompt_pulse(...)` (i.e. only when `Variant.PROMPT` is displayed via `display(...)`).
- Re-entry semantics: a second `display(PROMPT, ...)` while the trace is active resets `_progress` to 0.0 and re-runs from the start. The trace is never additive — there is at most one in flight at a time per prompt. This matches the pulse-in's "kill active tween, restart fresh" behavior.
- Hidden / cleared by `WasdPrompt.hide_prompt()` and `_reset_to_clean_state()` — the trace node clears `_active` and stops drawing.

## Architecture

### New node: `TraceBorder`

A `Control` child of `WasdPrompt`, custom-drawn via `_draw()`. Anchored to fill its parent so its `size` always matches the prompt box's current rendered size.

**Z-order:** sits between `Background` (ColorRect, yellow) and `Label`, so the WASD letter is never obscured by the trace.

**Public API:**

```gdscript
class_name TraceBorder
extends Control

func play_trace() -> void
func stop_trace() -> void
```

**Internal state:**

```gdscript
const _LAP_SECONDS := 0.20
const _TAIL_FRACTION := 1.0 / 3.0   # 1/3 of perimeter
const _SEGMENT_COUNT := 24
const _LINE_THICKNESS := 5.0
const _HEAD_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const _MID_COLOR := Color(1.0, 0.15, 0.75, 1.0)
const _TAIL_COLOR := Color(0.55, 0.10, 0.85, 0.0)

var _active: bool = false
var _progress: float = 0.0          # 0.0 → 1.0 over one lap
```

**`_process(delta)`** advances `_progress` while `_active`, calls `queue_redraw()` each frame, and clears `_active` when `_progress >= 1.0`.

**`_draw()`** computes head position from `_progress` and emits 24 line segments behind it, each at a `t` offset of `(i / _SEGMENT_COUNT) * _TAIL_FRACTION` *behind* the head. Each segment uses a 2-point `draw_line(a, b, color, _LINE_THICKNESS)` between two perimeter samples spaced `_TAIL_FRACTION / _SEGMENT_COUNT` apart.

### Perimeter sampling

Pure helper inside `TraceBorder`:

```gdscript
func _perimeter_point(t: float) -> Vector2
```

`t` is normalized into `[0, 1)` via `fposmod(t, 1.0)`. The rectangle has four edges of equal length (it's a square in practice, but the math handles non-square boxes too). For a box of size `(w, h)`:

- Total perimeter: `2 * (w + h)`
- Edge 0 (top): `t ∈ [0, w / P)` → `(t * P, 0)`
- Edge 1 (right): `t ∈ [w / P, (w + h) / P)` → `(w, (t * P - w))`
- Edge 2 (bottom): `t ∈ [(w + h) / P, (2*w + h) / P)` → `(w - (t * P - w - h), h)`
- Edge 3 (left): `t ∈ [(2*w + h) / P, 1)` → `(0, h - (t * P - 2*w - h))`

This is pure math — no scene needed to unit-test.

### Color sampling

```gdscript
func _trail_color(i: int) -> Color
```

For segment index `i` in `[0, _SEGMENT_COUNT)`, where `i = 0` is the head and `i = _SEGMENT_COUNT - 1` is the tail end:

- `u := i / float(_SEGMENT_COUNT - 1)` → `u ∈ [0, 1]`
- If `u < 0.5`: lerp `_HEAD_COLOR → _MID_COLOR` over `u * 2`.
- Else: lerp `_MID_COLOR → _TAIL_COLOR` over `(u - 0.5) * 2`.

### Integration with `WasdPrompt`

Two touch points:

1. **Scene:** add `TraceBorder` as a child of the `WasdPrompt` Control, between `Background` and `Label` in scene order. Anchored full-rect so it fills the box.

2. **Script (`wasd_prompt.gd`):**
   - Cache a typed reference: `@onready var _trace: TraceBorder = $TraceBorder`
   - In `_animate_prompt_pulse(duration_seconds)`, after `_kill_active_tween()` and before the first `tween_property` call, invoke `_trace.play_trace()`.
   - In `_reset_to_clean_state()` and `hide_prompt()`, invoke `_trace.stop_trace()` so a hide mid-trace clears the draw cleanly.
   - The four other animation functions (`_animate_block_shake`, `_animate_hit_toss`, `_animate_damage_double_pulse`, `_animate_miss_double_pulse`) make NO calls to `_trace` — verified by the test suite below.

## Out of scope

- No persistent border, no second loop after the first lap.
- No color or duration variation per opponent / per direction.
- No reactive behavior (the trace doesn't speed up, slow down, or change on player input — it's a one-shot at appearance).
- No shader work. Pure `_draw()` with `draw_line(...)`.
- Sound effects (none added).

## Testing

### Unit (GUT)

`tests/unit/test_trace_border.gd`

- `_perimeter_point(0.0)` returns `(0, 0)` for any box size.
- `_perimeter_point(0.25)` returns `(w, 0)` (top-right corner) for an `(w, h)` box.
- `_perimeter_point(0.5)` returns `(w, h)`.
- `_perimeter_point(0.75)` returns `(0, h)`.
- `_perimeter_point(1.0)` returns `(0, 0)` again (wraps via `fposmod`).
- `_perimeter_point(0.5 + 1.0)` returns the same point as `_perimeter_point(0.5)` (negative-offset / wrap robustness).
- `_trail_color(0)` returns `_HEAD_COLOR`.
- `_trail_color(_SEGMENT_COUNT - 1)` returns `_TAIL_COLOR`.
- `_trail_color(mid)` has alpha strictly between 0 and 1.

### Integration (extending `test_wasd_prompt_animation.gd`)

- Calling `display(direction, Variant.PROMPT, duration)` flips `_trace._active` to `true` on the same frame.
- Calling `display(direction, Variant.SUCCESS, duration)` (and the other three non-PROMPT variants) leaves `_trace._active == false`.
- Calling `hide_prompt()` while a trace is active sets `_trace._active = false`.

### Manual playtest verification

- Tofu match (0.8 s show, slow pace): trace reads clearly, completes well before the prompt settles.
- Sebastian match (0.35 s show, fast pace): trace still reads, fits inside the show window without clipping the fade-out.
- Block-success, attack-success, damage, and attack-miss flashes show NO trace (regression check).

## Files touched

- **New:** `scripts/ui/trace_border.gd`
- **New:** `tests/unit/test_trace_border.gd`
- **Modified:** `scenes/ui/wasd_prompt.tscn` (add `TraceBorder` child node)
- **Modified:** `scripts/ui/wasd_prompt.gd` (3 small additions: `_trace` reference, `play_trace()` call inside `_animate_prompt_pulse`, `stop_trace()` calls inside `hide_prompt` / `_reset_to_clean_state`)
- **Modified:** `tests/unit/test_wasd_prompt_animation.gd` (variant-gating tests)
