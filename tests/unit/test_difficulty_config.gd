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
