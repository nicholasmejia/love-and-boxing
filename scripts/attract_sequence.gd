extends Control

# ── Tunable constants ────────────────────────────────────────────────────────
# Audio
const TITLE_INTRO_LENGTH := 11.636  # measured length of title_intro.ogg
const MAIN_MENU_FADE_DURATION := 0.4

# Press-K pulse (CONTEXT.md: opacity 0.3 ↔ 1.0 over ~1.0s, sinusoidal)
const PRESS_K_PERIOD := 1.0
const PRESS_K_FLOOR := 0.3
const PRESS_K_CEILING := 1.0

# SFX hook keys (named constants so the bespoke-SFX follow-up is a one-line edit)
const SFX_CONFIRM := "menu_option_select"
# const SFX_PUNCH_IMPACT := "opponent_punch_body"      # wired in Task 10
# const SFX_PENNANT_FLYOFF := "swing"                  # wired in Task 10
# const SFX_PENNANT_WHOOSH := ""                       # TODO: bespoke clip
# const SFX_TITLE_SLAM := ""                           # TODO: bespoke clip

# ── State ────────────────────────────────────────────────────────────────────
enum Phase { SLIDE_IN, ATTRACT_PUNCH, CAMERA_PAN, TITLE_SLAM, SETTLE_HOLD, PRESS_K_FLASH, FADING_OUT }

var _phase: Phase = Phase.PRESS_K_FLASH
var _press_k_armed := false
var _press_k_tween: Tween = null
var _fade_tween: Tween = null

@onready var _press_k: Label = $PressK
@onready var _fade_overlay: ColorRect = $FadeOverlay

func _ready() -> void:
	AudioBus.play_music("title_main_loop")
	_fade_overlay.color = Color(0, 0, 0, 0)
	_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_press_k_pulse()
	_press_k_armed = true

func _unhandled_input(event: InputEvent) -> void:
	if _phase == Phase.FADING_OUT:
		return
	if event.is_action_pressed("menu_confirm") and _press_k_armed:
		_confirm_to_main_menu()

func _start_press_k_pulse() -> void:
	# Sinusoidal opacity pulse: floor → ceiling → floor every PRESS_K_PERIOD.
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
