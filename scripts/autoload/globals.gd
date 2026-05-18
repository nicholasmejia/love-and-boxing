extends Node

enum MatchOutcome { WIN, LOSE, DRAW }

var selected_difficulty: DifficultyConfig
var last_match_outcome: int = MatchOutcome.DRAW
var last_played_tier: int = 1

func clear_selection() -> void:
	selected_difficulty = null
