extends Control

const _SCROLL_SPEED := 110.0  # px/sec — calibrated for comfortable read
const _EXIT_FADE := 0.4

@onready var _scroll_content: VBoxContainer = $ScrollContent
@onready var _fade_overlay: ColorRect = $FadeOverlay

var _scroll_tween: Tween
var _exiting: bool = false

func _ready() -> void:
	AudioBus.play_music("menu")
	_fade_overlay.color = Color(0, 0, 0, 0)
	# Layout needs a frame to compute the VBox's final height (children's
	# minimum sizes settle on first sort_children pass).
	await get_tree().process_frame
	_start_scroll()

func _start_scroll() -> void:
	var viewport_height := get_viewport_rect().size.y
	var content_height := _scroll_content.size.y
	_scroll_content.position.y = viewport_height
	var end_y := -content_height
	var distance := viewport_height + content_height
	var duration := distance / _SCROLL_SPEED
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll_content, "position:y", end_y, duration) \
		.set_trans(Tween.TRANS_LINEAR)
	_scroll_tween.tween_callback(_finish)

func _unhandled_input(event: InputEvent) -> void:
	if _exiting:
		return
	if event.is_action_pressed("menu_confirm") or event.is_action_pressed("ui_cancel"):
		_finish()

func _finish() -> void:
	if _exiting:
		return
	_exiting = true
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	var t := create_tween()
	t.tween_property(_fade_overlay, "color:a", 1.0, _EXIT_FADE)
	t.tween_callback(SceneRouter.goto_main_menu)
