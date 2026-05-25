extends Control

const _INSTA_URL := "https://www.instagram.com/chomiegang"

@onready var _buttons: Array[Button] = [
	$VBoxContainer/StartButton,
	$VBoxContainer/OptionsButton,
	$VBoxContainer/CreditsButton,
	$VBoxContainer/QuitButton,
]
@onready var _coming_soon: Label = $ComingSoonLabel
@onready var _insta_link: TextureButton = $InstaLink

var _focus_index: int = 0

func _ready() -> void:
	_coming_soon.visible = false
	_update_focus()
	AudioBus.play_music("menu")
	$VBoxContainer/StartButton.pressed.connect(SceneRouter.goto_level_select)
	$VBoxContainer/OptionsButton.pressed.connect(SceneRouter.goto_options_menu)
	$VBoxContainer/CreditsButton.pressed.connect(SceneRouter.goto_credits)
	$VBoxContainer/QuitButton.pressed.connect(SceneRouter.quit_game)
	_insta_link.pressed.connect(_open_insta_link)

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

# Open the Instagram link in a new tab. On web, browsers heuristically classify
# OS.shell_open (which maps to window.open) as a "popup" and may block it; a
# programmatically-clicked <a target="_blank"> is treated as user navigation
# and almost always escapes the popup blocker — but only if the call stays
# synchronous inside this user-input handler so the browser's user-activation
# token is still live. Desktop builds fall through to OS.shell_open which
# launches the system default browser.
func _open_insta_link() -> void:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var js := """
		(function(){
			var a = document.createElement('a');
			a.href = '%s';
			a.target = '_blank';
			a.rel = 'noopener noreferrer';
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
		})();
		""" % _INSTA_URL
		JavaScriptBridge.eval(js, true)
	else:
		OS.shell_open(_INSTA_URL)
