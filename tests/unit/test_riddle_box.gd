extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

func _make_prompt(reactions: Array) -> DialoguePrompt:
	# reactions: 3-element array of String; pass "" for empty reaction.
	var p := DialoguePrompt.new()
	p.body_text = "body"
	var outcomes := [Outcome.Type.WRONG, Outcome.Type.NEUTRAL, Outcome.Type.RIGHT]
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcomes[i]
		a.reaction_text = reactions[i]
		p.answers.append(a)
	return p

func _mount() -> RiddleBox:
	var box: RiddleBox = RiddleBoxScene.instantiate()
	add_child_autoqfree(box)
	return box

func test_display_enters_normal_with_all_cards_visible():
	var box := _mount()
	# display() now resolves after typewriter + fade-in. await the full thing.
	await box.display(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible, "card should be visible after display() resolves")
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "card should be fully opaque after fade-in")

func test_show_reaction_hides_unpicked_cards_and_swaps_body_text():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	box.show_reaction(1)
	# show_reaction now tweens unpicked cards out over EXIT_DURATION; wait
	# for that to settle before asserting end-state visibility.
	await get_tree().create_timer(RiddleBox.EXIT_DURATION + 0.05).timeout
	assert_eq(box.get_state(), RiddleBox.State.REACTION)
	var cards := box.get_cards()
	assert_false(cards[0].visible, "unpicked left card should be hidden after exit tween")
	assert_true(cards[1].visible, "picked center card should remain visible")
	assert_false(cards[2].visible, "unpicked right card should be hidden after exit tween")

func test_show_reaction_with_empty_reaction_hides_box():
	var box := _mount()
	var prompt := _make_prompt(["", "", ""])  # tofu-shaped: no reactions
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(0)
	await get_tree().process_frame
	assert_false(box.visible)
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)  # state unchanged

func test_redisplay_from_reaction_returns_to_normal_with_all_cards():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	box.show_reaction(2)
	await get_tree().process_frame
	# Re-display via display() runs the typewriter + fade again.
	await box.display(prompt)
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
		assert_almost_eq(card.modulate.a, 1.0, 0.01)

# --- Render gate contract (Riddle Render Gate, see CONTEXT.md) ---

func test_display_is_awaitable_and_resolves_after_typewriter_and_fade():
	var box := _mount()
	# body="body" → 4 chars at default 60 cps ≈ 67ms typewriter, plus
	# FADE_IN_DURATION ≈ 150ms fade-in.
	var prompt := _make_prompt(["r0", "r1", "r2"])
	var t_start := Time.get_ticks_msec()
	await box.display(prompt)
	var elapsed_ms := Time.get_ticks_msec() - t_start
	assert_false(box.is_rendering(), "is_rendering should be false after display() resolves")
	# Resolution must include both the typewriter and the fade-in.
	var min_expected_ms := 30 + int(RiddleBox.FADE_IN_DURATION * 1000.0) - 20
	assert_true(elapsed_ms >= min_expected_ms, "display() should await typewriter + fade — expected ≥%dms, got %dms" % [min_expected_ms, elapsed_ms])

func test_body_render_complete_signal_fires_after_typewriter():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	var fired := [false]
	box.body_render_complete.connect(func(): fired[0] = true)
	box.display(prompt)
	# Wait for typewriter to complete.
	await get_tree().create_timer(0.3).timeout
	assert_true(fired[0], "body_render_complete should emit when typewriter finishes naturally")

func test_display_instant_shows_full_text_synchronously():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display_instant(prompt)
	# No await — text should be fully visible immediately, no typewriter running.
	assert_false(box.is_rendering(), "display_instant should not start typewriter")
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)

func test_confirm_is_suppressed_while_body_is_typing():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	var emitted: Array = []
	box.answer_submitted.connect(func(outcome): emitted.append(outcome))
	box.display(prompt)
	await get_tree().process_frame
	assert_true(box.is_rendering())
	# Synthesize a menu_confirm press while is_rendering is true.
	var ev := InputEventAction.new()
	ev.action = "menu_confirm"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "K-confirm during typewriter must not emit answer_submitted")

func test_confirm_works_after_typewriter_completes():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	var emitted: Array = []
	box.answer_submitted.connect(func(outcome): emitted.append(outcome))
	box.display(prompt)
	# Wait for typewriter to complete ("body" = 4 chars).
	await get_tree().create_timer(0.3).timeout
	assert_false(box.is_rendering())
	var ev := InputEventAction.new()
	ev.action = "menu_confirm"
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	assert_eq(emitted.size(), 1, "K-confirm after render should emit answer_submitted")
