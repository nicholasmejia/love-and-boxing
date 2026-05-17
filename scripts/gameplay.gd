extends Control

func _ready() -> void:
	Globals.last_played_tier = 1
	Globals.last_match_outcome = Globals.MatchOutcome.WIN
	$CenterContainer/EndButton.pressed.connect(SceneRouter.goto_match_results)
