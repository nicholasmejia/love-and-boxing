extends Node

const TITLE := "res://scenes/title_screen.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAMEPLAY := "res://scenes/gameplay.tscn"
const MATCH_RESULTS := "res://scenes/match_results.tscn"

func goto_title() -> void:
	get_tree().change_scene_to_file(TITLE)

func goto_level_select() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)

func goto_gameplay() -> void:
	get_tree().change_scene_to_file(GAMEPLAY)

func goto_match_results() -> void:
	get_tree().change_scene_to_file(MATCH_RESULTS)

func quit_game() -> void:
	get_tree().quit()
