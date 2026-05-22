extends Control

func _ready() -> void:
	# TODO: full Attract Sequence animation. For now, route to Main Menu so
	# the game remains bootable while later tasks build out the content.
	call_deferred("_route_to_main_menu")

func _route_to_main_menu() -> void:
	SceneRouter.goto_main_menu()
