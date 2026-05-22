extends Node

const ATTRACT_SEQUENCE := "res://scenes/attract_sequence.tscn"
const MAIN_MENU := "res://scenes/main_menu.tscn"
const LEVEL_SELECT := "res://scenes/level_select.tscn"
const GAMEPLAY := "res://scenes/gameplay.tscn"
const MATCH_RESULTS := "res://scenes/match_results.tscn"

func goto_attract_sequence() -> void:
	get_tree().change_scene_to_file(ATTRACT_SEQUENCE)

func goto_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU)

func goto_level_select() -> void:
	get_tree().change_scene_to_file(LEVEL_SELECT)

func goto_gameplay() -> void:
	get_tree().change_scene_to_file(GAMEPLAY)

func goto_match_results() -> void:
	get_tree().change_scene_to_file(MATCH_RESULTS)

func quit_game() -> void:
	get_tree().quit()
