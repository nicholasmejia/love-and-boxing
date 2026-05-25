extends Control

@onready var _buttons: Array[Button] = [
	$VBoxContainer/StartButton,
	$VBoxContainer/OptionsButton,
	$VBoxContainer/CreditsButton,
	$VBoxContainer/QuitButton,
]
@onready var _coming_soon: Label = $ComingSoonLabel

var _focus_index: int = 0

func _ready() -> void:
	_coming_soon.visible = false
	_update_focus()
	AudioBus.play_music("menu")
	$VBoxContainer/StartButton.pressed.connect(SceneRouter.goto_level_select)
	$VBoxContainer/OptionsButton.pressed.connect(SceneRouter.goto_options_menu)
	$VBoxContainer/CreditsButton.pressed.connect(SceneRouter.goto_credits)
	$VBoxContainer/QuitButton.pressed.connect(SceneRouter.quit_game)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_up"):
		_focus_index = (_focus_index - 1 + _buttons.size()) % _buttons.size()
		_update_focus()
	elif event.is_action_pressed("menu_down"):
		_focus_index = (_focus_index + 1) % _buttons.size()
		_update_focus()
	elif event.is_action_pressed("menu_confirm"):
		_buttons[_focus_index].pressed.emit()
	elif event.is_action_pressed("ui_cancel"):
		SceneRouter.goto_attract_sequence()

func _update_focus() -> void:
	_buttons[_focus_index].grab_focus()

func _show_coming_soon() -> void:
	_coming_soon.visible = true
	await get_tree().create_timer(1.0).timeout
	_coming_soon.visible = false
