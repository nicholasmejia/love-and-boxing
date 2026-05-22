extends Control

# ── Tunable constants ────────────────────────────────────────────────────────
# Audio (master clock = title_intro.ogg measured length)
const TITLE_INTRO_LENGTH := 11.636
const MAIN_MENU_FADE_DURATION := 0.4

# Title Slam (phase 4)
const SLAM_DURATION := 0.636                    # 11.0 → 11.636
const SLAM_START_OFFSET_Y := -800.0             # off-screen above
const SLAM_START_SCALE := Vector2(1.3, 1.3)
const FLASH_DECAY := 0.25                       # white → clear

# Slide-In (phase 1) — strict sequential: Tofu → Minty → Sebastian
const SLIDE_IN_PER_CHARACTER := 1.0             # 1.0s × 3 = 3.0 total (snappier landing)
const SLIDE_IN_DISTANCE := 1400.0               # px; off-screen start offset
const SLIDE_IN_TRANS := Tween.TRANS_QUART       # clean decel, minimal overshoot
const SLIDE_IN_EASE := Tween.EASE_OUT

# Pre-Punch Hold — pennants sit assembled at rest before the punch fires
const PRE_PUNCH_HOLD := 2.0

# Attract Punch (phase 2)
const PUNCH_DURATION := 1.7                     # 5.0 → 6.7
const PUNCH_GROW_DURATION := 0.2                # punch wind-up (2.5× faster than before)
const PUNCH_PEAK_SCALE := Vector2(2.5, 2.5)     # more aggressive growth
const PUNCH_REST_SCALE := Vector2(1.0, 1.0)
const PUNCH_FADE_OVERLAP := 0.6                 # fades to 0 during early camera pan
const FLY_OFF_DURATION := 1.5                   # rise + fall; heavier airborne feel
const FLY_RISE_DURATION := 0.6                  # impact → apex (decelerating)
const FLY_FALL_DURATION := 0.9                  # apex → off-screen below (gravity)
const FLY_APEX_OFFSET_Y := -500.0               # how high above rest the pennants peak
const FLY_FINAL_DROP := 1400.0                  # how far below rest they fall (off-screen)
const FLY_HORIZONTAL_SPREAD := 200.0            # sideways drift at apex per pennant
const FLY_OFF_SPIN_DEGREES := 180.0             # half-rotation tumble (heavy, slow)

# Camera Pan (phase 3) — three parallax layers: background, ring, characters
const PAN_DURATION := 4.3                       # 6.7 → 11.0
const PAN_BACKGROUND_RISE := 200.0              # px; background starts this far below rest (1.0× reference)
const PAN_RING_MULTIPLIER := 1.6                # ring rises this much faster than background
const PAN_CHARACTER_MULTIPLIER := 2.4           # characters rise faster still (closest layer)
const PAN_TRANS := Tween.TRANS_SINE
const PAN_EASE := Tween.EASE_OUT

# Phase windows (cumulative time-since-scene-start)
const SLIDE_IN_TOTAL := SLIDE_IN_PER_CHARACTER * 3.0                                          # 3.0
const PUNCH_START_TIME := SLIDE_IN_TOTAL + PRE_PUNCH_HOLD                                      # 5.0
const PAN_START_TIME := PUNCH_START_TIME + PUNCH_DURATION                                      # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                                    # 11.0
# Invariant: PAN_START_TIME + PAN_DURATION == SLAM_START_TIME (asserted in _ready).

# Settle Hold (phase 5)
const SETTLE_HOLD := 2.0

# Press-K Flash (phase 6)
const PRESS_K_PERIOD := 1.0
const PRESS_K_FLOOR := 0.3
const PRESS_K_CEILING := 1.0

# SFX hook keys (named so the bespoke-SFX follow-up is a one-line edit per key).
const SFX_CONFIRM := "menu_option_select"
const SFX_PUNCH_IMPACT := "opponent_punch_body"
const SFX_PENNANT_FLYOFF := "swing"
# TODO bespoke clips (planned follow-up — see memory project_attract_sequence_sfx_followup):
#   const SFX_PENNANT_WHOOSH := "attract_pennant_whoosh"  # one per slide-in start, 3 calls
#   const SFX_TITLE_SLAM := "title_slam"                  # at slam impact frame

# ── State ────────────────────────────────────────────────────────────────────
enum Phase { SLIDE_IN, ATTRACT_PUNCH, CAMERA_PAN, TITLE_SLAM, SETTLE_HOLD, PRESS_K_FLASH, FADING_OUT }

var _phase: Phase = Phase.TITLE_SLAM
var _press_k_armed := false
var _press_k_tween: Tween = null
var _fade_tween: Tween = null
var _slam_tween: Tween = null
var _settle_timer: SceneTreeTimer = null
var _phase_wait_timer: SceneTreeTimer = null
var _skip_requested := false
var _title_text_rest_y: float = 0.0

@onready var _title_text: TextureRect = $TitleText
@onready var _press_k: Label = $PressK
@onready var _white_flash: ColorRect = $WhiteFlash
@onready var _fade_overlay: ColorRect = $FadeOverlay
@onready var _title_background: TextureRect = $TitleBackground
@onready var _title_ring: TextureRect = $TitleRing
@onready var _title_tofu: TextureRect = $TitleTofu
@onready var _title_minty: TextureRect = $TitleMinty
@onready var _title_sebastian: TextureRect = $TitleSebastian
@onready var _attract_punch: TextureRect = $AttractPunch
@onready var _pennant_tofu: TextureRect = $PennantTofu
@onready var _pennant_minty: TextureRect = $PennantMinty
@onready var _pennant_sebastian: TextureRect = $PennantSebastian

var _bg_rest_y: float
var _ring_rest_y: float
var _tofu_rest_y: float
var _minty_rest_y: float
var _sebastian_rest_y: float

func _ready() -> void:
	_fade_overlay.color = Color(0, 0, 0, 0)
	assert(is_equal_approx(PAN_START_TIME + PAN_DURATION, SLAM_START_TIME),
		"Phase budget invariant: pan must end exactly when slam starts")
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white_flash.color = Color(1, 1, 1, 0)
	_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press_k.modulate.a = 0.0  # hidden until phase 6
	_prepare_title_text_offscreen()
	_prepare_camera_pan_offscreen()
	_prepare_attract_punch()
	_prepare_slide_in_offscreen()
	AudioBus.play_music("title_intro")
	_run_sequence()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("menu_confirm"):
		return
	match _phase:
		Phase.FADING_OUT:
			return
		Phase.PRESS_K_FLASH:
			if _press_k_armed:
				_confirm_to_main_menu()
		Phase.SETTLE_HOLD:
			_fast_forward_settle()
		Phase.SLIDE_IN, Phase.ATTRACT_PUNCH, Phase.CAMERA_PAN, Phase.TITLE_SLAM:
			_skip_to_rest()

# ── Phase orchestration ──────────────────────────────────────────────────────

func _run_sequence() -> void:
	await _play_slide_in()
	await get_tree().create_timer(PRE_PUNCH_HOLD).timeout
	await _play_attract_punch()
	_start_punch_fadeout()
	await _play_camera_pan()
	await _play_title_slam()
	await _settle_hold()
	_enter_press_k_flash()

func _prepare_title_text_offscreen() -> void:
	_title_text.pivot_offset = _title_text.size * 0.5
	_title_text_rest_y = _title_text.position.y
	_title_text.position.y += SLAM_START_OFFSET_Y
	_title_text.scale = SLAM_START_SCALE

func _prepare_camera_pan_offscreen() -> void:
	_bg_rest_y = _title_background.position.y
	_ring_rest_y = _title_ring.position.y
	_tofu_rest_y = _title_tofu.position.y
	_minty_rest_y = _title_minty.position.y
	_sebastian_rest_y = _title_sebastian.position.y
	_title_background.position.y = _bg_rest_y + PAN_BACKGROUND_RISE
	_title_background.modulate.a = 0.0
	var ring_rise := PAN_BACKGROUND_RISE * PAN_RING_MULTIPLIER
	var character_rise := PAN_BACKGROUND_RISE * PAN_CHARACTER_MULTIPLIER
	_title_ring.position.y = _ring_rest_y + ring_rise
	_title_tofu.position.y = _tofu_rest_y + character_rise
	_title_minty.position.y = _minty_rest_y + character_rise
	_title_sebastian.position.y = _sebastian_rest_y + character_rise
	# Foreground stand-ups stay invisible until the camera pan reveals them.
	_title_ring.modulate.a = 0.0
	_title_tofu.modulate.a = 0.0
	_title_minty.modulate.a = 0.0
	_title_sebastian.modulate.a = 0.0

var _pennant_rest_positions := {}

func _prepare_slide_in_offscreen() -> void:
	# Each pennant starts off-screen toward the edge closest to its rest position.
	# Tofu (left) → from left, Minty (right) → from right, Sebastian (bottom) → from bottom.
	_pennant_rest_positions[_pennant_tofu] = _pennant_tofu.position
	_pennant_rest_positions[_pennant_minty] = _pennant_minty.position
	_pennant_rest_positions[_pennant_sebastian] = _pennant_sebastian.position
	_pennant_tofu.position.x -= SLIDE_IN_DISTANCE
	_pennant_minty.position.x += SLIDE_IN_DISTANCE
	_pennant_sebastian.position.y += SLIDE_IN_DISTANCE

func _play_slide_in() -> void:
	_phase = Phase.SLIDE_IN
	# TODO play_sfx(SFX_PENNANT_WHOOSH) once authored — three calls, one per slide-in start.
	await _slide_pennant(_pennant_tofu)
	await _slide_pennant(_pennant_minty)
	await _slide_pennant(_pennant_sebastian)

func _slide_pennant(pennant: TextureRect) -> void:
	var rest_position: Vector2 = _pennant_rest_positions[pennant]
	var tween := create_tween()
	tween.tween_property(pennant, "position", rest_position, SLIDE_IN_PER_CHARACTER).set_trans(SLIDE_IN_TRANS).set_ease(SLIDE_IN_EASE)
	await tween.finished

func _prepare_attract_punch() -> void:
	_attract_punch.scale = PUNCH_REST_SCALE
	# Hidden until the wind-up grow ramps it to visible.
	_attract_punch.modulate.a = 0.0
	_attract_punch.pivot_offset = _attract_punch.size * 0.5
	for pennant in [_pennant_tofu, _pennant_minty, _pennant_sebastian]:
		pennant.pivot_offset = pennant.size * 0.5

func _play_attract_punch() -> void:
	_phase = Phase.ATTRACT_PUNCH
	# Wind-up: punch grows AND fades in from behind the pennant composite.
	var grow_tween := create_tween().set_parallel(true)
	grow_tween.tween_property(_attract_punch, "scale", PUNCH_PEAK_SCALE, PUNCH_GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	grow_tween.tween_property(_attract_punch, "modulate:a", 1.0, PUNCH_GROW_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await grow_tween.finished
	AudioBus.play_sfx(SFX_PUNCH_IMPACT)
	AudioBus.play_sfx(SFX_PENNANT_FLYOFF)
	# Impact: pennants get tossed straight up, arc, then fall off-screen.
	# Punch shrinks back during the same window.
	var punch_shrink := create_tween()
	punch_shrink.tween_property(_attract_punch, "scale", PUNCH_REST_SCALE, FLY_OFF_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_toss_pennant(_pennant_tofu, -FLY_HORIZONTAL_SPREAD, -FLY_OFF_SPIN_DEGREES)
	_toss_pennant(_pennant_minty, FLY_HORIZONTAL_SPREAD, FLY_OFF_SPIN_DEGREES)
	_toss_pennant(_pennant_sebastian, 0.0, FLY_OFF_SPIN_DEGREES)
	await punch_shrink.finished

func _toss_pennant(pennant: TextureRect, x_drift: float, spin_degrees: float) -> void:
	# Two-stage arc: rise to apex (EASE_OUT, decelerating against "gravity"),
	# then fall off-screen below (EASE_IN, gravity-accelerated). Spin runs in
	# parallel at a linear rate for a slow, heavy tumble.
	var start_pos := pennant.position
	var apex := Vector2(start_pos.x + x_drift * 0.5, start_pos.y + FLY_APEX_OFFSET_Y)
	var end_pos := Vector2(start_pos.x + x_drift, start_pos.y + FLY_FINAL_DROP)
	var arc := create_tween()
	arc.tween_property(pennant, "position", apex, FLY_RISE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(pennant, "position", end_pos, FLY_FALL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var spin := create_tween()
	spin.tween_property(pennant, "rotation_degrees", spin_degrees, FLY_OFF_DURATION).set_trans(Tween.TRANS_LINEAR)

func _start_punch_fadeout() -> void:
	var fade := create_tween()
	fade.tween_property(_attract_punch, "modulate:a", 0.0, PUNCH_FADE_OVERLAP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_camera_pan() -> void:
	_phase = Phase.CAMERA_PAN
	var pan_tween := create_tween().set_parallel(true)
	pan_tween.tween_property(_title_background, "position:y", _bg_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_background, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_ring, "position:y", _ring_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_ring, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_tofu, "position:y", _tofu_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_tofu, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_minty, "position:y", _minty_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_minty, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_sebastian, "position:y", _sebastian_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_sebastian, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	await pan_tween.finished

func _play_title_slam() -> void:
	_phase = Phase.TITLE_SLAM
	_slam_tween = create_tween().set_parallel(true)
	_slam_tween.tween_property(_title_text, "position:y", _title_text_rest_y, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_slam_tween.tween_property(_title_text, "scale", Vector2.ONE, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _slam_tween.finished
	# TODO: AudioBus.play_sfx(SFX_TITLE_SLAM) once a bespoke title slam clip is authored.
	# Impact frame: cross-cut music and fire flash simultaneously.
	AudioBus.play_music("title_main_loop")
	_white_flash.color.a = 1.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_white_flash, "color:a", 0.0, FLASH_DECAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await flash_tween.finished

func _settle_hold() -> void:
	_phase = Phase.SETTLE_HOLD
	await get_tree().create_timer(SETTLE_HOLD).timeout

func _enter_press_k_flash() -> void:
	_phase = Phase.PRESS_K_FLASH
	_start_press_k_pulse()
	_press_k_armed = true

func _start_press_k_pulse() -> void:
	_press_k.modulate.a = PRESS_K_FLOOR
	_press_k_tween = create_tween().set_loops()
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_CEILING, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)
	_press_k_tween.tween_property(_press_k, "modulate:a", PRESS_K_FLOOR, PRESS_K_PERIOD * 0.5).set_trans(Tween.TRANS_SINE)

func _confirm_to_main_menu() -> void:
	_phase = Phase.FADING_OUT
	AudioBus.play_sfx(SFX_CONFIRM)
	if _press_k_tween and _press_k_tween.is_valid():
		_press_k_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_overlay, "color:a", 1.0, MAIN_MENU_FADE_DURATION)
	_fade_tween.tween_callback(SceneRouter.goto_main_menu)

func _skip_to_rest() -> void:
	# Snap every animated element to its rest state; cross-cut audio to the main loop;
	# enter phase 5 entry. Phase 5 still holds for its full SETTLE_HOLD duration.
	# Note: the original phase coroutine awaits never resume after kill — that's
	# intentional; they orphan harmlessly and are reaped on scene change.
	_skip_requested = true
	_kill_sequence_tweens()
	# Pennants: hide them (they would have flown off by now in the natural flow).
	for pennant in [_pennant_tofu, _pennant_minty, _pennant_sebastian]:
		pennant.modulate.a = 0.0
	# Punch: hidden.
	_attract_punch.modulate.a = 0.0
	# Camera pan endpoints: every layer to rest.
	_title_background.modulate.a = 1.0
	_title_background.position.y = _bg_rest_y
	_title_ring.position.y = _ring_rest_y
	_title_tofu.position.y = _tofu_rest_y
	_title_minty.position.y = _minty_rest_y
	_title_sebastian.position.y = _sebastian_rest_y
	_title_ring.modulate.a = 1.0
	_title_tofu.modulate.a = 1.0
	_title_minty.modulate.a = 1.0
	_title_sebastian.modulate.a = 1.0
	# Title slam endpoint.
	_title_text.position.y = _title_text_rest_y
	_title_text.scale = Vector2.ONE
	# White flash: brief decay starting now.
	_white_flash.color.a = 1.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_white_flash, "color:a", 0.0, FLASH_DECAY).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Audio: hard-start the main loop from t=0.
	AudioBus.play_music("title_main_loop")
	# Resume into settle hold from this point.
	_run_post_skip()

func _fast_forward_settle() -> void:
	# Cut the settle hold short and jump straight into phase 6.
	# SceneTreeTimer has no kill API; we drop the ref and directly enter phase 6.
	_settle_timer = null
	_skip_requested = true
	_enter_press_k_flash()

func _run_post_skip() -> void:
	_phase = Phase.SETTLE_HOLD
	_settle_timer = get_tree().create_timer(SETTLE_HOLD)
	await _settle_timer.timeout
	_settle_timer = null
	if _phase != Phase.PRESS_K_FLASH:  # only enter if fast-forward didn't already
		_enter_press_k_flash()

func _kill_sequence_tweens() -> void:
	# Kill every active tween created on this node. _press_k_tween is left alone —
	# it only starts in phase 6 (post-skip) and the skip path doesn't touch it.
	for tween in get_tree().get_processed_tweens():
		if tween.is_valid():
			tween.kill()
