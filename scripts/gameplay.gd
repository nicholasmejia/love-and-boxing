extends Control

func _ready() -> void:
	$CenterContainer/EndButton.pressed.connect(SceneRouter.goto_match_results)
