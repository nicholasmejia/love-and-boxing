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

func test_wrong_input_emits_failure_with_expected_direction():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var failed := {"emitted": false, "direction": -1}
	a.attack_failed.connect(func(direction):
		failed["emitted"] = true
		failed["direction"] = direction)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	var step: int = a._sequence.steps()[0]
	var wrong := SimonSequence.Direction.HEAD if step != SimonSequence.Direction.HEAD else SimonSequence.Direction.BODY
	a.player_input(wrong)
	assert_true(failed["emitted"])
	assert_eq(failed["direction"], step, "attack_failed carries the missed step's direction")

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
	var failed := {"emitted": false, "direction": -1}
	a.attack_failed.connect(func(direction):
		failed["emitted"] = true
		failed["direction"] = direction)
	a._sequence.seed_rng(1)
	a.begin(1)
	# Wait past show (interlude + step + gap ~= 0.012s) + input window (0.05s).
	await get_tree().create_timer(0.2).timeout
	assert_true(failed["emitted"], "attack_failed must fire when the input window expires with no input")
	assert_eq(failed["direction"], a.current_sequence().steps()[0], "timeout fail carries the expected direction at _expected_index")

func test_first_input_received_emits_on_first_repeat_press():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"count": 0}
	a.first_input_received.connect(func(): fired["count"] += 1)
	a._sequence.seed_rng(1)
	a.begin(2)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	a.player_input(a._sequence.steps()[1])
	assert_eq(fired["count"], 1, "first_input_received must fire exactly once")

func test_first_input_received_fires_on_wrong_direction_too():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"emitted": false}
	a.first_input_received.connect(func(): fired["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	# Send a deliberately wrong direction: the opposite of step[0].
	# Directions enum is in SimonSequence (UP=0,DOWN=1,LEFT=2,RIGHT=3 — read from
	# scripts/game/simon_sequence.gd). Sending step+1 mod 4 guarantees mismatch.
	var wrong: int = (a._sequence.steps()[0] + 1) % 4
	a.player_input(wrong)
	assert_true(fired["emitted"], "wrong-direction input must still fire first_input_received")

func test_first_input_received_does_not_fire_before_repeat_phase():
	var a := AttackPhase.new()
	a.step_seconds = 10.0  # long show phase, never reaches repeat
	a.gap_seconds = 0.01
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"emitted": false}
	a.first_input_received.connect(func(): fired["emitted"] = true)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.05).timeout
	a.player_input(a._sequence.steps()[0])  # show phase still running; _repeat_active is false
	assert_false(fired["emitted"], "show-phase input must NOT fire first_input_received")

func test_first_input_received_resets_per_begin():
	var a := AttackPhase.new()
	a.step_seconds = 0.001
	a.gap_seconds = 0.001
	a.interlude_seconds = 0.01
	a.input_window_seconds = 10.0
	add_child_autoqfree(a)
	var fired := {"count": 0}
	a.first_input_received.connect(func(): fired["count"] += 1)
	a._sequence.seed_rng(1)
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	a.begin(1)
	await get_tree().create_timer(0.1).timeout
	a.player_input(a._sequence.steps()[0])
	assert_eq(fired["count"], 2, "first_input_received must fire once per begin()")
