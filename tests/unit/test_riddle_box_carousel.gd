extends GutTest

const RiddleBoxScene := preload("res://scenes/ui/riddle_box.tscn")

# Mirrors the helper in test_riddle_box.gd. Inline here so this file is
# self-contained — carousel behavior tests live separately from the
# baseline RiddleBox contract tests.
func _make_prompt(reactions: Array) -> DialoguePrompt:
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

func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

# --- Phase A: cycle input mapping ---

func test_j_decrements_highlight_with_wrap():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# Default highlight is middle (index 1). One J → 0. Another J → 2 (wraps).
	assert_eq(box._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "one J should land on index 0")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 2, "second J should wrap to index 2")

func test_l_increments_highlight_with_wrap():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(box._highlight_index, 1)
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 2, "one L should land on index 2")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "second L should wrap to index 0")

func test_i_is_noop_in_riddle_box():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# Move highlight off the default with one J so we can detect any
	# spurious "snap to middle" behavior.
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0)
	_send_action("menu_up")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 0, "menu_up must not change the highlight inside RiddleBox")

# --- Phase B Task 3: at-rest carousel layout ---

func test_display_lays_out_cards_with_center_at_full_scale_sides_shrunk():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := box.get_cards()
	# Middle card (index 1) is the default center → full scale.
	assert_almost_eq(cards[1].scale.x, 1.0, 0.001, "default center card should be at full scale")
	assert_almost_eq(cards[1].scale.y, 1.0, 0.001)
	# Cards 0 and 2 are side cards → SIDE_SCALE.
	assert_almost_eq(cards[0].scale.x, RiddleBox.SIDE_SCALE, 0.001, "left side card should be at SIDE_SCALE")
	assert_almost_eq(cards[2].scale.x, RiddleBox.SIDE_SCALE, 0.001, "right side card should be at SIDE_SCALE")

func test_cycle_swaps_which_card_is_at_full_scale():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Initial: card 1 is center.
	assert_almost_eq(box.get_cards()[1].scale.x, 1.0, 0.001)
	# One L: center_index becomes 2; card 2 should now be at full scale once
	# the rotation tween completes.
	_send_action("menu_right")
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION + 0.05).timeout
	assert_almost_eq(box.get_cards()[2].scale.x, 1.0, 0.001, "after L, card 2 should be at center")
	assert_almost_eq(box.get_cards()[1].scale.x, RiddleBox.SIDE_SCALE, 0.001, "after L, card 1 should be at SIDE_SCALE")

# --- Phase B Task 4: rotation animation + queue + K-lock ---

func test_two_rapid_l_presses_land_on_target_via_queue():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Initial center is index 1. Two L presses: 1 → 2 → 0 (wraps).
	_send_action("menu_right")
	# Don't await — fire the second press while the first tween is in flight.
	_send_action("menu_right")
	# Wait for both tweens: 2 × ROTATION_DURATION + slack.
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION * 2.5).timeout
	assert_eq(box._highlight_index, 0, "two queued L presses should land on index 0 (wrap)")

func test_third_input_during_rotation_is_dropped_not_stacked():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	# Three rapid L presses: queue depth 1 means we should land on index 0
	# (1 → 2 from first press, 2 → 0 from the queued second; third is dropped).
	_send_action("menu_right")
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION * 2.5).timeout
	assert_eq(box._highlight_index, 0, "third press should be dropped — final index is 0, not 1")

func test_confirm_during_rotation_is_rejected():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	box.answer_submitted.connect(func(o): emitted.append(o))
	# Start a rotation, then press K before it finishes.
	_send_action("menu_right")
	await get_tree().process_frame  # Tween has started; _is_rotating should be true.
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "K during rotation must not emit answer_submitted")
	# After the tween completes, K should be accepted.
	await get_tree().create_timer(RiddleBox.ROTATION_DURATION + 0.05).timeout
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 1, "K after rotation completes should emit answer_submitted")

# --- Phase B Task 5: visibility timing ---

func test_cards_invisible_during_typewriter_for_text_body():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	# Sample one frame in — typewriter is running, cards should be alpha 0.
	await get_tree().process_frame
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 0.0, 0.01, "card should be transparent during typewriter")

func test_cards_fade_to_full_opacity_after_typewriter():
	var box := _mount()
	# display() awaits both typewriter and fade-in by Task 5's contract.
	await box.display(_make_prompt(["r0", "r1", "r2"]))
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "card should be fully opaque after display() resolves")

func test_display_instant_skips_fade_cards_immediately_visible():
	var box := _mount()
	box.display_instant(_make_prompt(["r0", "r1", "r2"]))
	# No await — display_instant is synchronous and skips the fade.
	for card in box.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "display_instant should show cards at full opacity immediately")

func test_jl_locked_while_fading_in():
	var box := _mount()
	box.display(_make_prompt(["r0", "r1", "r2"]))
	# "body" = 4 chars at 60 cps ≈ 67ms typewriter; FADE_IN_DURATION = 150ms.
	# Wait 120ms: typewriter is done, fade is in flight (started at ~67ms, ends
	# at ~217ms). At 120ms the fade has been running ~53ms → alpha ≈ 0.35.
	await get_tree().create_timer(0.12).timeout
	# _is_fading_in should be true; any alpha in (0, 1) satisfies the check.
	assert_almost_eq(box.get_cards()[1].modulate.a, 0.0, 0.99, "still fading in (alpha < 1)")  # any value 0..1
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(box._highlight_index, 1, "J/L must be ignored during fade-in")

# --- Phase B Task 6: side-card exit on confirm ---

func test_unpicked_cards_animate_out_with_alpha_and_position():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	await box.display(prompt)
	# Capture starting positions of side cards (index 0 and 2 — middle is picked).
	var cards := box.get_cards()
	var start_pos_0: Vector2 = cards[0].position
	var start_pos_2: Vector2 = cards[2].position
	box.show_reaction(1)
	# Sample mid-tween (~half of EXIT_DURATION in).
	await get_tree().create_timer(RiddleBox.EXIT_DURATION * 0.5).timeout
	# Mid-tween: side cards should be partway to off-screen AND partially faded.
	assert_true(cards[0].modulate.a < 0.9, "left card alpha should be tweening down")
	assert_true(cards[2].modulate.a < 0.9, "right card alpha should be tweening down")
	assert_true(cards[0].position != start_pos_0, "left card position should be tweening toward off-screen")
	assert_true(cards[2].position != start_pos_2, "right card position should be tweening toward off-screen")
