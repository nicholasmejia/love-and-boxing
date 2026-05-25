extends Control

# Row layout: 0 = BGM slider, 1 = SFX slider, 2 = Reset Progress, 3 = Go Back.
# Up/Down moves between rows, Left/Right adjusts the focused slider, K fires
# the focused button, Esc returns to the main menu.

const _SLIDER_STEP := 5

@onready var _bgm_slider: HSlider = $VBoxContainer/BgmRow/Slider
@onready var _bgm_value: Label = $VBoxContainer/BgmRow/Value
@onready var _sfx_slider: HSlider = $VBoxContainer/SfxRow/Slider
@onready var _sfx_value: Label = $VBoxContainer/SfxRow/Value
@onready var _reset_button: Button = $VBoxContainer/ResetButton
@onready var _back_button: Button = $VBoxContainer/BackButton
@onready var _reset_feedback: Label = $ResetFeedback

@onready var _focusables: Array[Control] = [_bgm_slider, _sfx_slider, _reset_button, _back_button]
var _focus_index: int = 0

func _ready() -> void:
	AudioBus.play_music("menu")
	_reset_feedback.visible = false
	_bgm_slider.value = SaveData.bgm_volume_percent()
	_sfx_slider.value = SaveData.sfx_volume_percent()
	_bgm_value.text = str(int(_bgm_slider.value))
	_sfx_value.text = str(int(_sfx_slider.value))
	_bgm_slider.value_changed.connect(_on_bgm_changed)
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_back_button.pressed.connect(SceneRouter.goto_main_menu)
	_update_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SceneRouter.goto_main_menu()
		return
	if event.is_action_pressed("menu_up"):
		_focus_index = (_focus_index - 1 + _focusables.size()) % _focusables.size()
		_update_focus()
	elif event.is_action_pressed("menu_down"):
		_focus_index = (_focus_index + 1) % _focusables.size()
		_update_focus()
	elif event.is_action_pressed("menu_left"):
		_nudge_focused_slider(-_SLIDER_STEP)
	elif event.is_action_pressed("menu_right"):
		_nudge_focused_slider(_SLIDER_STEP)
	elif event.is_action_pressed("menu_confirm"):
		var focused := _focusables[_focus_index]
		if focused is Button:
			(focused as Button).pressed.emit()

func _update_focus() -> void:
	_focusables[_focus_index].grab_focus()

func _nudge_focused_slider(delta: int) -> void:
	var focused := _focusables[_focus_index]
	if focused is HSlider:
		var slider := focused as HSlider
		slider.value = clamp(slider.value + delta, slider.min_value, slider.max_value)

func _on_bgm_changed(value: float) -> void:
	var percent := int(value)
	_bgm_value.text = str(percent)
	AudioBus.set_bgm_volume_percent(percent)

func _on_sfx_changed(value: float) -> void:
	var percent := int(value)
	_sfx_value.text = str(percent)
	AudioBus.set_sfx_volume_percent(percent)

func _on_reset_pressed() -> void:
	SaveData.reset()
	_reset_feedback.visible = true
	await get_tree().create_timer(1.0).timeout
	_reset_feedback.visible = false
