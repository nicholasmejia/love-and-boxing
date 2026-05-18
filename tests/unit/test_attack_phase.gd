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

func test_multi_step_sequence_advances_through_inputs():
	# Guards against an off-by-one in the `_expected_index >= _sequence.length()`
	# check by feeding all three steps and asserting attack_succeeded fires
	# exactly once and only after the final input.
	var a := AttackPhase.new()
	a.step_seconds = 0.01
	a.gap_seconds = 0.01
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var counter := {"successes": 0}
	a.attack_succeeded.connect(func(): counter["successes"] += 1)
	a._sequence.seed_rng(1)
	a.begin(3)
	await get_tree().create_timer(0.2).timeout
	var steps := a.current_sequence().steps()
	assert_eq(steps.size(), 3, "begin(3) should produce a 3-step sequence")
	a.player_input(steps[0])
	assert_eq(counter["successes"], 0, "no success after first of three inputs")
	a.player_input(steps[1])
	assert_eq(counter["successes"], 0, "no success after second of three inputs")
	a.player_input(steps[2])
	assert_eq(counter["successes"], 1, "success fires exactly once after the third input")

func test_timeout_emits_failure():
	# Exercises _on_input_timeout -> _fail() by letting the input window expire
	# with no player_input calls.
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 0.05
	add_child_autoqfree(a)
	var failed := {"emitted": false}
	a.attack_failed.connect(func(): failed["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	# Wait past show (interlude + step + gap ~= 0.012s) + input window (0.05s).
	await get_tree().create_timer(0.2).timeout
	assert_true(failed["emitted"], "attack_failed must fire when the input window expires with no input")
