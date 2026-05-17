extends Control

@onready var _cards: Array[Button] = [
	$HBoxContainer/TofuCard,
	$HBoxContainer/MintyCard,
	$HBoxContainer/SebastianCard,
]

var _focus_index: int = 0

func _ready() -> void:
	_cards[0].pressed.connect(func(): _select_tier(1))
	_cards[1].pressed.connect(func(): _select_tier(2))
	_cards[2].pressed.connect(func(): _select_tier(3))
	_update_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_left"):
		_focus_index = (_focus_index - 1 + _cards.size()) % _cards.size()
		_update_focus()
	elif event.is_action_pressed("menu_right"):
		_focus_index = (_focus_index + 1) % _cards.size()
		_update_focus()
	elif event.is_action_pressed("menu_confirm"):
		_cards[_focus_index].pressed.emit()

func _update_focus() -> void:
	_cards[_focus_index].grab_focus()

func _select_tier(tier: int) -> void:
	SceneRouter.goto_gameplay()  # No difficulty wiring yet; just navigates.
