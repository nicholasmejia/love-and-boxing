extends Control

@onready var _cards: Array[Button] = [
	$HBoxContainer/TofuCard,
	$HBoxContainer/MintyCard,
	$HBoxContainer/SebastianCard,
]

var _focus_index: int = 0

func _ready() -> void:
	_apply_lock_states()
	_cards[0].pressed.connect(func(): _select_tier(1))
	_cards[1].pressed.connect(func(): _select_tier(2))
	_cards[2].pressed.connect(func(): _select_tier(3))
	_update_focus()

func _apply_lock_states() -> void:
	var unlocked := SaveData.unlocked_tier()
	for i in _cards.size():
		var tier := i + 1
		var card := _cards[i]
		var locked := tier > unlocked
		card.disabled = locked
		card.modulate = Color(0.4, 0.4, 0.4) if locked else Color.WHITE
		if locked:
			card.text = card.text.replace(" (Easy)", "").replace(" (Medium)", "").replace(" (Hard)", "")
			card.text = "[LOCKED]\n" + card.text

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left"):
		_focus_index = (_focus_index - 1 + _cards.size()) % _cards.size()
		_update_focus()
	elif event.is_action_pressed("menu_right"):
		_focus_index = (_focus_index + 1) % _cards.size()
		_update_focus()
	elif event.is_action_pressed("menu_confirm"):
		var tier := _focus_index + 1
		if tier <= SaveData.unlocked_tier():
			_cards[_focus_index].pressed.emit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_wipe_progress()

func _update_focus() -> void:
	_cards[_focus_index].grab_focus()

func _select_tier(tier: int) -> void:
	SceneRouter.goto_gameplay()

func _wipe_progress() -> void:
	var path := "user://progress.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("[LevelSelect] Progress wiped. Restart for changes to apply.")
