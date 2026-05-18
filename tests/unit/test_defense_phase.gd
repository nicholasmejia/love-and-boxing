extends GutTest

func test_correct_input_emits_step_blocked():
	var d := DefensePhase.new()
	d.step_seconds = 0.01
	d.gap_seconds = 0.01
	d.interlude_seconds = 0.01
	add_child_autoqfree(d)
	var flags := {"seen": false}
	d.step_blocked.connect(func(_idx): flags["seen"] = true)
	d._sequence.seed_rng(1)
	d._sequence.reset()
	d._sequence.extend()
	var step: int = d._sequence.steps()[0]
	d.begin_repeat_phase()
	d.player_input(step)
	assert_true(flags["seen"])

func test_wrong_input_emits_damage_taken():
	var d := DefensePhase.new()
	add_child_autoqfree(d)
	var flags := {"emitted": false}
	d.damage_taken.connect(func(): flags["emitted"] = true)
	d._sequence.seed_rng(1)
	d._sequence.extend()
	var step: int = d._sequence.steps()[0]
	var wrong := SimonSequence.Direction.HEAD
	if step == SimonSequence.Direction.HEAD:
		wrong = SimonSequence.Direction.BODY
	d.begin_repeat_phase()
	d.player_input(wrong)
	assert_true(flags["emitted"])

func test_sequence_completed_when_last_step_correct():
	var d := DefensePhase.new()
	add_child_autoqfree(d)
	var flags := {"emitted": false}
	d.sequence_completed.connect(func(): flags["emitted"] = true)
	d._sequence.seed_rng(1)
	d._sequence.reset()
	d._sequence.extend()
	d._sequence.extend()
	var steps := d._sequence.steps()
	d.begin_repeat_phase()
	d.player_input(steps[0])
	# After last correct input, sequence_completed should fire; the phase is NOT
	# running, so no new round will start in the background.
	d.player_input(steps[1])
	assert_true(flags["emitted"])

func test_player_input_noop_when_repeat_inactive():
	var d := DefensePhase.new()
	add_child_autoqfree(d)
	var flags := {"blocked": false, "damaged": false}
	d.step_blocked.connect(func(_idx): flags["blocked"] = true)
	d.damage_taken.connect(func(): flags["damaged"] = true)
	d._sequence.seed_rng(1)
	d._sequence.extend()
	# _repeat_active stays false; input should be ignored.
	d.player_input(d._sequence.steps()[0])
	assert_false(flags["blocked"])
	assert_false(flags["damaged"])
