extends Control

@onready var _outcome_label: Label = $CenterContainer/VBox/Outcome
@onready var _unlock_label: Label = $CenterContainer/VBox/UnlockLabel

func _ready() -> void:
	_outcome_label.text = _outcome_text()
	_unlock_label.visible = false
	# Results is treated as part of the menu loop — the stinger has already
	# played on the YOU_WIN / YOU_LOSE banner in gameplay. If it's still
	# audible when we land here (K-skip mid-stinger), the 0.5s cross-fade
	# bridges the stinger tail into menu music; if the stinger already
	# finished naturally, this is a 0.5s fade-in from silence.
	AudioBus.play_music("menu", 0.5)
	if Globals.last_match_outcome == Globals.MatchOutcome.WIN:
		var next_tier := Globals.last_played_tier + 1
		if next_tier <= 3 and next_tier > SaveData.unlocked_tier():
			SaveData.unlock_tier(next_tier)
			_unlock_label.text = "Unlocked tier %d!" % next_tier
			_unlock_label.visible = true
	if _beat_sebastian():
		$CenterContainer/VBox/ReturnButton.text = "Roll Credits (K)"
	$CenterContainer/VBox/ReturnButton.pressed.connect(_advance)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_confirm"):
		_advance()

func _advance() -> void:
	if _beat_sebastian():
		SceneRouter.goto_credits()
	else:
		SceneRouter.goto_level_select()

func _beat_sebastian() -> bool:
	return Globals.last_match_outcome == Globals.MatchOutcome.WIN and Globals.last_played_tier == 3

func _outcome_text() -> String:
	match Globals.last_match_outcome:
		Globals.MatchOutcome.WIN: return "You Win!"
		Globals.MatchOutcome.LOSE: return "You Lose!"
		_: return "Draw!"
