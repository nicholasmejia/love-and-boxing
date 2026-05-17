extends Control

func _ready() -> void:
	$CenterContainer/VBox/ReturnButton.pressed.connect(SceneRouter.goto_level_select)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu_confirm"):
		SceneRouter.goto_level_select()
