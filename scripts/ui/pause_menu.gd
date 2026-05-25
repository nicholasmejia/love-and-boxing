class_name PauseMenu
extends Control

@onready var _resume_button: Button = $VBoxContainer/ResumeButton
@onready var _give_up_button: Button = $VBoxContainer/GiveUpButton

var _buttons: Array[Button] = []
var _focus_index: int = 0

func _ready() -> void:
	_buttons = [_resume_button, _give_up_button]
	_resume_button.pressed.connect(close)
	_give_up_button.pressed.connect(_on_give_up)

func is_open() -> bool:
	return visible

func open() -> void:
	if visible:
		return
	visible = true
	get_tree().paused = true
	_focus_index = 0
	_update_focus()

func close() -> void:
	if not visible:
		return
	get_tree().paused = false
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("menu_up"):
		get_viewport().set_input_as_handled()
		_focus_index = (_focus_index - 1 + _buttons.size()) % _buttons.size()
		_update_focus()
	elif event.is_action_pressed("menu_down"):
		get_viewport().set_input_as_handled()
		_focus_index = (_focus_index + 1) % _buttons.size()
		_update_focus()
	elif event.is_action_pressed("menu_confirm"):
		# Mark handled BEFORE the button fires — Resume's close() unpauses the
		# tree mid-dispatch, which could otherwise let the same K event bubble
		# into the answer carousel and pick an answer the moment we return.
		get_viewport().set_input_as_handled()
		_buttons[_focus_index].pressed.emit()

func _update_focus() -> void:
	_buttons[_focus_index].grab_focus()

func _on_give_up() -> void:
	get_tree().paused = false
	SceneRouter.goto_level_select()
