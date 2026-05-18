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
	var flags := {"emitted": false, "direction": -1}
	d.damage_taken.connect(func(direction):
		flags["emitted"] = true
		flags["direction"] = direction)
	d._sequence.seed_rng(1)
	d._sequence.extend()
	var step: int = d._sequence.steps()[0]
	var wrong := SimonSequence.Direction.HEAD
	if step == SimonSequence.Direction.HEAD:
		wrong = SimonSequence.Direction.BODY
	d.begin_repeat_phase()
	d.player_input(wrong)
	assert_true(flags["emitted"])
	assert_eq(flags["direction"], step, "damage_taken carries the missed step's direction")

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
	d.damage_taken.connect(func(_direction): flags["damaged"] = true)
	d._sequence.seed_rng(1)
	d._sequence.extend()
	# _repeat_active stays false; input should be ignored.
	d.player_input(d._sequence.steps()[0])
	assert_false(flags["blocked"])
	assert_false(flags["damaged"])

func _make_fast_defense_phase() -> DefensePhase:
	var d := DefensePhase.new()
	d.step_seconds = 0.001
	d.gap_seconds = 0.001
	d.interlude_seconds = 0.001
	d.input_window_seconds = 10.0
	return d

func test_replay_keeps_existing_chain_length():
	var d := _make_fast_defense_phase()
	add_child_autoqfree(d)
	var captured := {"steps": null}
	d.show_started.connect(func(steps): captured["steps"] = steps.duplicate())
	d._sequence.seed_rng(1)
	d._sequence.extend()
	d._sequence.extend()
	# Chain is length 2 — replay must NOT extend or reset it.
	d.replay()
	# Wait long enough for interlude_seconds + show loop to run.
	await get_tree().create_timer(0.2).timeout
	assert_not_null(captured["steps"], "show_started should fire from replay")
	assert_eq(captured["steps"].size(), 2, "replay must re-run the existing length, not extend or reset")

func test_replay_emits_show_completed_then_repeat_started():
	var d := _make_fast_defense_phase()
	add_child_autoqfree(d)
	var order: Array = []
	d.show_completed.connect(func(): order.append("show_completed"))
	d.repeat_started.connect(func(): order.append("repeat_started"))
	d._sequence.seed_rng(1)
	d._sequence.extend()
	d.replay()
	await get_tree().create_timer(0.2).timeout
	assert_eq(order.size(), 2, "expected both show_completed and repeat_started to fire")
	assert_eq(order[0], "show_completed")
	assert_eq(order[1], "repeat_started")

func test_replay_after_stop_resumes():
	var d := _make_fast_defense_phase()
	add_child_autoqfree(d)
	var flags := {"show_started": false}
	d.show_started.connect(func(_steps): flags["show_started"] = true)
	d._sequence.seed_rng(1)
	d._sequence.extend()
	d.stop()
	# After stop(), _running is false. replay() must flip it back to true.
	d.replay()
	await get_tree().create_timer(0.2).timeout
	assert_true(flags["show_started"], "replay must re-set _running so the show phase fires")

func test_stop_then_start_cancels_in_flight_show_loop():
	# Reproduces the M9 WRONG-outcome race: an in-flight show loop from the
	# OLD chain was emitting step_flashed for its remaining steps after stop()
	# then start() flipped _running back to true. With the generation token,
	# only the NEW chain (length 1 after start's reset) emits step_flashed.
	#
	# Timing setup: per-step gap is long (0.2s) so the OLD loop is guaranteed
	# to be mid-await when we cancel and restart. interlude is small so the
	# NEW chain's single step runs within the post-cancel wait window.
	var d := DefensePhase.new()
	d.step_seconds = 0.01
	d.gap_seconds = 0.2
	d.interlude_seconds = 0.001
	d.input_window_seconds = 10.0
	add_child_autoqfree(d)
	# Wrap in dict so the lambda captures by reference (GDScript captures
	# locals by value otherwise — see test_correct_input_emits_step_blocked).
	var counter := {"steps": 0}
	d.step_flashed.connect(func(_dir): counter["steps"] += 1)

	# Seed a length-3 sequence and start the show loop manually so we know
	# exactly how many emissions to expect if the loop is NOT canceled.
	d._sequence.seed_rng(1)
	d._sequence.extend()
	d._sequence.extend()
	d._sequence.extend()
	d._running = true
	d._generation += 1
	d._run_show_then_repeat()

	# Yield long enough for the old loop to emit its FIRST step_flashed and
	# enter the long gap-await for step 2, but short enough that steps 2 and
	# 3 have NOT yet emitted.
	await get_tree().create_timer(0.05).timeout
	var old_count_before: int = counter["steps"]
	assert_eq(old_count_before, 1, "sanity: old loop should have emitted exactly 1 step before cancel; got %d" % old_count_before)

	# Cancel + restart. start() resets the sequence to length 0 then extends
	# to length 1, so the NEW chain has exactly 1 step. With the generation
	# token, the old loop's pending awaits must bail before emitting steps 2/3.
	d.stop()
	d.start()

	# Wait long enough for: (a) the OLD loop's remaining gap-await (~0.2s) to
	# resolve and try to continue (it must bail via generation check), and
	# (b) the NEW chain to complete its single show step.
	await get_tree().create_timer(0.4).timeout

	# Expect: 1 from old loop (before cancel) + 1 from new chain = 2.
	# Without the generation token, the old loop would leak steps 2 and 3 (= 4 total).
	var leaked: int = counter["steps"] - 2
	assert_eq(counter["steps"], 2, "stop+start must cancel the in-flight show loop; leaked %d extra step_flashed emissions after cancel" % leaked)
