extends Control

const TIER_CONFIGS := [
	"res://data/difficulty/tofu.tres",
	"res://data/difficulty/minty.tres",
	"res://data/difficulty/sebastian.tres",
]

@onready var _cards: Array[Button] = [
	$HBoxContainer/TofuCard,
	$HBoxContainer/MintyCard,
	$HBoxContainer/SebastianCard,
]

var _focus_index: int = 0
var _card_labels: Array[String] = []

func _ready() -> void:
	_apply_lock_states()
	_cards[0].pressed.connect(func(): _select_tier(1))
	_cards[1].pressed.connect(func(): _select_tier(2))
	_cards[2].pressed.connect(func(): _select_tier(3))
	_update_focus()
	AudioBus.play_music("menu")

func _apply_lock_states() -> void:
	if _card_labels.is_empty():
		for card in _cards:
			_card_labels.append(card.text)
	var unlocked := SaveData.unlocked_tier()
	for i in _cards.size():
		var tier := i + 1
		var card := _cards[i]
		var locked := tier > unlocked
		card.disabled = locked
		card.modulate = Color(0.4, 0.4, 0.4) if locked else Color.WHITE
		if locked:
			card.text = "[LOCKED]\n" + _card_labels[i]
		else:
			card.text = _card_labels[i]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left"):
		_focus_index = (_focus_index - 1 + _cards.size()) % _cards.size()
		_update_focus()
		AudioBus.play_sfx("menu_change_item")
	elif event.is_action_pressed("menu_right"):
		_focus_index = (_focus_index + 1) % _cards.size()
		_update_focus()
		AudioBus.play_sfx("menu_change_item")
	elif event.is_action_pressed("menu_confirm"):
		var tier := _focus_index + 1
		if tier <= SaveData.unlocked_tier():
			AudioBus.play_sfx("menu_option_select")
			_cards[_focus_index].pressed.emit()
	elif event.is_action_pressed("ui_cancel"):
		SceneRouter.goto_main_menu()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_wipe_progress()

func _update_focus() -> void:
	_cards[_focus_index].grab_focus()

func _select_tier(tier: int) -> void:
	var path: String = TIER_CONFIGS[tier - 1]
	Globals.selected_difficulty = load(path) as DifficultyConfig
	SceneRouter.goto_gameplay()

func _wipe_progress() -> void:
	SaveData.reset()
	_apply_lock_states()
	print("[LevelSelect] Progress wiped.")
