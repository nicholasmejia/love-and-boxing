extends Control

# ── Tunable constants ────────────────────────────────────────────────────────
# Audio (master clock = title_intro.ogg measured length)
const TITLE_INTRO_LENGTH := 11.636
const MAIN_MENU_FADE_DURATION := 0.4

# Title Slam (phase 4)
const SLAM_DURATION := 0.636                    # 11.0 → 11.636
const SLAM_START_TIME := TITLE_INTRO_LENGTH - SLAM_DURATION
const SLAM_START_OFFSET_Y := -800.0             # off-screen above
const SLAM_START_SCALE := Vector2(1.3, 1.3)
const FLASH_DECAY := 0.25                       # white → clear

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

func _ready() -> void:
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_white_flash.color = Color(1, 1, 1, 0)
	_white_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press_k.modulate.a = 0.0  # hidden until phase 6
	_prepare_title_text_offscreen()
	AudioBus.play_music("title_intro")
	_run_sequence()

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.FADING_OUT:
		return
	if event.is_action_pressed("menu_confirm") and _press_k_armed:
		_confirm_to_main_menu()

# ── Phase orchestration ──────────────────────────────────────────────────────

func _run_sequence() -> void:
	# Phases 1–3 are placeholder waits in this task — Tasks 6/7/8 fill them in.
	# Their cumulative duration must equal SLAM_START_TIME.
	await get_tree().create_timer(SLAM_START_TIME).timeout
	await _play_title_slam()
	await _settle_hold()
	_enter_press_k_flash()

func _prepare_title_text_offscreen() -> void:
	_title_text.pivot_offset = _title_text.size * 0.5
	_title_text.position.y += SLAM_START_OFFSET_Y
	_title_text.scale = SLAM_START_SCALE

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
