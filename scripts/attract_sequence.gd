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

# Attract Punch (phase 2)
const PUNCH_DURATION := 1.6                     # 5.1 → 6.7
const PUNCH_GROW_DURATION := 0.5                # punch wind-up before pennants fly
const PUNCH_PEAK_SCALE := Vector2(1.6, 1.6)
const PUNCH_REST_SCALE := Vector2(1.0, 1.0)
const PUNCH_FADE_OVERLAP := 0.6                 # fades to 0 during early camera pan
const FLY_OFF_DURATION := 1.1                   # 5.6 → 6.7 (after grow start at +0.5)
const FLY_OFF_DISTANCE := 1400.0                # px; how far each pennant travels
const FLY_OFF_SPIN_DEGREES := 180.0

# Camera Pan (phase 3)
const PAN_DURATION := 4.3                       # 6.7 → 11.0
const PAN_BACKGROUND_RISE := 200.0              # px; background starts this far below rest
const PAN_FOREGROUND_MULTIPLIER := 1.6          # foreground rises this much faster
const PAN_TRANS := Tween.TRANS_SINE
const PAN_EASE := Tween.EASE_OUT

# Phase windows (cumulative time-since-scene-start)
const PUNCH_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION - PUNCH_DURATION  # 5.1
const PAN_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION - PAN_DURATION                     # 6.7
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION                                    # 11.0

# Settle Hold (phase 5)
const SETTLE_HOLD := 2.0

# Press-K Flash (phase 6)
const PRESS_K_PERIOD := 1.0
const PRESS_K_FLOOR := 0.3
const PRESS_K_CEILING := 1.0

# SFX hook keys
const SFX_CONFIRM := "menu_option_select"
# const SFX_PUNCH_IMPACT := "opponent_punch_body"      # wired in Task 10
# const SFX_PENNANT_FLYOFF := "swing"                  # wired in Task 10
# const SFX_PENNANT_WHOOSH := ""                       # TODO: bespoke clip
# const SFX_TITLE_SLAM := ""                           # TODO: bespoke clip

# ── State ────────────────────────────────────────────────────────────────────
enum Phase { SLIDE_IN, ATTRACT_PUNCH, CAMERA_PAN, TITLE_SLAM, SETTLE_HOLD, PRESS_K_FLASH, FADING_OUT }

var _phase: Phase = Phase.TITLE_SLAM
var _press_k_armed := false
var _press_k_tween: Tween = null
var _fade_tween: Tween = null
var _slam_tween: Tween = null

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
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white_flash.color = Color(1, 1, 1, 0)
	_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press_k.modulate.a = 0.0  # hidden until phase 6
	_prepare_title_text_offscreen()
	_prepare_camera_pan_offscreen()
	_prepare_attract_punch()
	AudioBus.play_music("title_intro")
	_run_sequence()

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.FADING_OUT:
		return
	if event.is_action_pressed("menu_confirm") and _press_k_armed:
		_confirm_to_main_menu()

# ── Phase orchestration ──────────────────────────────────────────────────────

func _run_sequence() -> void:
	# Phase 1 (Slide-In) is still placeholder in this task — Task 8 fills it in.
	# Its duration must equal PUNCH_START_TIME.
	await get_tree().create_timer(PUNCH_START_TIME).timeout
	await _play_attract_punch()
	_start_punch_fadeout()
	await _play_camera_pan()
	await _play_title_slam()
	await _settle_hold()
	_enter_press_k_flash()

func _prepare_title_text_offscreen() -> void:
	_title_text.pivot_offset = _title_text.size * 0.5
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
	var fg_rise := PAN_BACKGROUND_RISE * PAN_FOREGROUND_MULTIPLIER
	_title_ring.position.y = _ring_rest_y + fg_rise
	_title_tofu.position.y = _tofu_rest_y + fg_rise
	_title_minty.position.y = _minty_rest_y + fg_rise
	_title_sebastian.position.y = _sebastian_rest_y + fg_rise

func _prepare_attract_punch() -> void:
	_attract_punch.scale = PUNCH_REST_SCALE
	_attract_punch.modulate.a = 1.0
	_attract_punch.pivot_offset = _attract_punch.size * 0.5
	for pennant in [_pennant_tofu, _pennant_minty, _pennant_sebastian]:
		pennant.pivot_offset = pennant.size * 0.5

func _play_attract_punch() -> void:
	_phase = Phase.ATTRACT_PUNCH
	# Wind-up: punch grows from behind the pennant composite.
	var grow_tween := create_tween()
	grow_tween.tween_property(_attract_punch, "scale", PUNCH_PEAK_SCALE, PUNCH_GROW_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await grow_tween.finished
	# Impact: pennants begin spin + fly-off; punch starts shrinking back.
	var fly_tween := create_tween().set_parallel(true)
	fly_tween.tween_property(_attract_punch, "scale", PUNCH_REST_SCALE, FLY_OFF_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_schedule_pennant_flyoff(fly_tween, _pennant_tofu, Vector2(-1.0, -0.6).normalized(), -FLY_OFF_SPIN_DEGREES)
	_schedule_pennant_flyoff(fly_tween, _pennant_minty, Vector2(1.0, -0.6).normalized(), FLY_OFF_SPIN_DEGREES)
	_schedule_pennant_flyoff(fly_tween, _pennant_sebastian, Vector2(0.0, 1.0).normalized(), FLY_OFF_SPIN_DEGREES)
	await fly_tween.finished

func _schedule_pennant_flyoff(tween: Tween, pennant: TextureRect, direction: Vector2, spin_degrees: float) -> void:
	var target_position := pennant.position + direction * FLY_OFF_DISTANCE
	tween.tween_property(pennant, "position", target_position, FLY_OFF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(pennant, "rotation_degrees", spin_degrees, FLY_OFF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _start_punch_fadeout() -> void:
	var fade := create_tween()
	fade.tween_property(_attract_punch, "modulate:a", 0.0, PUNCH_FADE_OVERLAP).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _play_camera_pan() -> void:
	_phase = Phase.CAMERA_PAN
	var pan_tween := create_tween().set_parallel(true)
	pan_tween.tween_property(_title_background, "position:y", _bg_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_background, "modulate:a", 1.0, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_ring, "position:y", _ring_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_tofu, "position:y", _tofu_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_minty, "position:y", _minty_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	pan_tween.tween_property(_title_sebastian, "position:y", _sebastian_rest_y, PAN_DURATION).set_trans(PAN_TRANS).set_ease(PAN_EASE)
	await pan_tween.finished

func _play_title_slam() -> void:
	_phase = Phase.TITLE_SLAM
	var rest_y := _title_text.position.y - SLAM_START_OFFSET_Y
	_slam_tween = create_tween().set_parallel(true)
	_slam_tween.tween_property(_title_text, "position:y", rest_y, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_slam_tween.tween_property(_title_text, "scale", Vector2.ONE, SLAM_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _slam_tween.finished
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
