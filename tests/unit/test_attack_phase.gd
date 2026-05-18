extends GutTest

func test_attack_phase_uses_combo_input_count():
	var a := AttackPhase.new()
	a.step_seconds = 0.01
	a.gap_seconds = 0.01
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	a.begin(2)
	assert_eq(a.expected_inputs(), 2)

func test_complete_sequence_emits_success():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var done := {"emitted": false}
	a.attack_succeeded.connect(func(): done["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	var step: int = a._sequence.steps()[0]
	a.player_input(step)
	assert_true(done["emitted"])

func test_wrong_input_emits_failure():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var failed := {"emitted": false}
	a.attack_failed.connect(func(): failed["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	var step: int = a._sequence.steps()[0]
	var wrong := SimonSequence.Direction.HEAD if step != SimonSequence.Direction.HEAD else SimonSequence.Direction.BODY
	a.player_input(wrong)
	assert_true(failed["emitted"])
