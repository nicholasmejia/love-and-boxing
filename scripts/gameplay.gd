extends Control

func _ready() -> void:
	$CenterContainer/EndButton.pressed.connect(SceneRouter.goto_match_results)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_confirm"):
		SceneRouter.goto_match_results()
