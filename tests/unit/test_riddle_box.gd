extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

func _make_prompt() -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = "body"
	var outcomes := [Outcome.Type.WRONG, Outcome.Type.NEUTRAL, Outcome.Type.RIGHT]
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcomes[i]
		a.reaction_text = "r%d" % i
		p.answers.append(a)
	return p

func _mount() -> RiddleBox:
	var box: RiddleBox = RiddleBoxScene.instantiate()
	add_child_autoqfree(box)
	return box

func test_display_enters_normal_state():
	var box := _mount()
	await box.display(_make_prompt())
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)

func test_show_reaction_transitions_to_reaction_state():
	var box := _mount()
	await box.display(_make_prompt())
	box.show_reaction("a reaction")
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.REACTION)

func test_display_is_awaitable_and_resolves_after_typewriter():
	var box := _mount()
	# body="body" → 4 chars at default 60 cps ≈ 67ms typewriter (no fade —
	# that lives in AnswerCarousel now).
	var t_start := Time.get_ticks_msec()
	await box.display(_make_prompt())
	var elapsed_ms := Time.get_ticks_msec() - t_start
	assert_false(box.is_rendering(), "is_rendering should be false after display() resolves")
	assert_true(elapsed_ms >= 30, "display() should await typewriter — expected ≥30ms, got %dms" % elapsed_ms)

func test_body_render_complete_signal_fires_after_typewriter():
	var box := _mount()
	var fired := [false]
	box.body_render_complete.connect(func(): fired[0] = true)
	box.display(_make_prompt())
	await get_tree().create_timer(0.3).timeout
	assert_true(fired[0], "body_render_complete should emit when typewriter finishes naturally")

func test_display_instant_shows_full_text_synchronously():
	var box := _mount()
	box.display_instant(_make_prompt())
	assert_false(box.is_rendering(), "display_instant should not start typewriter")
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)

func test_show_reaction_starts_reaction_typewriter():
	var box := _mount()
	await box.display(_make_prompt())
	# show_reaction is awaitable — resolves after the reaction typewriter completes.
	var t_start := Time.get_ticks_msec()
	await box.show_reaction("hello")
	var elapsed_ms := Time.get_ticks_msec() - t_start
	# "hello" = 5 chars at 60 cps ≈ 83ms.
	assert_true(elapsed_ms >= 30, "show_reaction should await typewriter — expected ≥30ms, got %dms" % elapsed_ms)
	assert_false(box.is_rendering(), "is_rendering should be false after show_reaction resolves")
