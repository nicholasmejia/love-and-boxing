extends GutTest

func test_difficulty_config_holds_pacing_values():
	var d := DifficultyConfig.new()
	d.show_phase_step_seconds = 0.6
	d.repeat_phase_window_seconds = 2.5
	d.opponent_slug = "minty"
	assert_almost_eq(d.show_phase_step_seconds, 0.6, 0.001)
	assert_almost_eq(d.repeat_phase_window_seconds, 2.5, 0.001)
	assert_eq(d.opponent_slug, "minty")

func test_default_values():
	var d := DifficultyConfig.new()
	assert_eq(d.opponent_slug, "")
	assert_eq(d.tier, 1)
	assert_almost_eq(d.show_phase_step_seconds, 0.8, 0.001)
	assert_almost_eq(d.repeat_phase_window_seconds, 3.0, 0.001)
	assert_eq(d.dialogue_deck_path, "")
	assert_eq(d.animation_profile_path, "")

func test_tofu_resource_loads_with_expected_values():
	var d: DifficultyConfig = load("res://data/difficulty/tofu.tres")
	assert_not_null(d, "tofu.tres should load")
	assert_eq(d.opponent_slug, "tofu")
	assert_eq(d.tier, 1)
	assert_almost_eq(d.show_phase_step_seconds, 0.8, 0.001)
	assert_almost_eq(d.repeat_phase_window_seconds, 3.0, 0.001)
	assert_eq(d.dialogue_deck_path, "res://data/dialogue/tofu/deck.tres")
	assert_eq(d.animation_profile_path, "res://data/opponent_animation/tofu.tres")

func test_minty_resource_loads_with_expected_values():
	var d: DifficultyConfig = load("res://data/difficulty/minty.tres")
	assert_not_null(d, "minty.tres should load")
	assert_eq(d.opponent_slug, "minty")
	assert_eq(d.tier, 2)
	assert_almost_eq(d.show_phase_step_seconds, 0.55, 0.001)
	assert_almost_eq(d.repeat_phase_window_seconds, 2.5, 0.001)
	assert_eq(d.dialogue_deck_path, "res://data/dialogue/minty/deck.tres")
	assert_eq(d.animation_profile_path, "")

func test_sebastian_resource_loads_with_expected_values():
	var d: DifficultyConfig = load("res://data/difficulty/sebastian.tres")
	assert_not_null(d, "sebastian.tres should load")
	assert_eq(d.opponent_slug, "sebastian")
	assert_eq(d.tier, 3)
	assert_almost_eq(d.show_phase_step_seconds, 0.35, 0.001)
	assert_almost_eq(d.repeat_phase_window_seconds, 2.0, 0.001)
	assert_eq(d.dialogue_deck_path, "")
	assert_eq(d.animation_profile_path, "")
