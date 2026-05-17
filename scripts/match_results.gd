extends Control

func _ready() -> void:
	$CenterContainer/VBox/ReturnButton.pressed.connect(SceneRouter.goto_level_select)
