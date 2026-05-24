extends GutTest

const AnswerCarouselScene := preload("res://scenes/ui/answer_carousel.tscn")

# Builds a prompt with three text answers and the given reaction strings.
# reactions: 3-element Array of String; pass "" for empty reaction (Tofu shape).
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

# Builds a prompt where all three answers carry the same outcome. Lets a test
# K-press any card and know exactly which outcome path the carousel will run,
# bypassing the per-display shuffle in display_prompt.
func _make_prompt_all(outcome: int) -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = "body"
	for i in 3:
		var a := DialogueAnswer.new()
		a.text = "answer_%d" % i
		a.outcome = outcome
		a.reaction_text = "r"
		p.answers.append(a)
	return p

func _mount() -> AnswerCarousel:
	var c: AnswerCarousel = AnswerCarouselScene.instantiate()
	add_child_autoqfree(c)
	return c

func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)

# --- Phase A: cycle input mapping ---

func test_j_decrements_highlight_with_wrap():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(c._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "one J should land on index 0")
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 2, "second J should wrap to index 2")

func test_l_increments_highlight_with_wrap():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	assert_eq(c._highlight_index, 1, "default highlight should be middle")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 2, "one L should land on index 2")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "second L should wrap to index 0")

func test_i_is_noop_in_carousel():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	_send_action("menu_left")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0)
	_send_action("menu_up")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 0, "menu_up must not change the highlight inside AnswerCarousel")

# --- At-rest layout ---

func test_display_lays_out_cards_with_center_at_full_scale_sides_shrunk():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	assert_almost_eq(cards[1].scale.x, 1.0, 0.001, "default center card should be at full scale")
	assert_almost_eq(cards[1].scale.y, 1.0, 0.001)
	assert_almost_eq(cards[0].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "left side card should be at SIDE_SCALE")
	assert_almost_eq(cards[2].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "right side card should be at SIDE_SCALE")

func test_cycle_swaps_which_card_is_at_full_scale():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_almost_eq(c.get_cards()[1].scale.x, 1.0, 0.001)
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION + 0.05).timeout
	assert_almost_eq(c.get_cards()[2].scale.x, 1.0, 0.001, "after L, card 2 should be at center")
	assert_almost_eq(c.get_cards()[1].scale.x, AnswerCarousel.SIDE_SCALE, 0.001, "after L, card 1 should be at SIDE_SCALE")

# --- Rotation + queue + K-lock ---

func test_two_rapid_l_presses_land_on_target_via_queue():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION * 2.5).timeout
	assert_eq(c._highlight_index, 0, "two queued L presses should land on index 0 (wrap)")

func test_third_input_during_rotation_is_dropped_not_stacked():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	_send_action("menu_right")
	_send_action("menu_right")
	_send_action("menu_right")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION * 2.5).timeout
	assert_eq(c._highlight_index, 0, "third press should be dropped — final index is 0, not 1")

func test_confirm_during_rotation_is_rejected():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append([outcome, picked]))
	_send_action("menu_right")
	await get_tree().process_frame  # tween started
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "K during rotation must not emit answer_submitted")
	await get_tree().create_timer(AnswerCarousel.ROTATION_DURATION + 0.05).timeout
	_send_action("menu_confirm")
	# Emit is now deferred to impact frame — wait for GLOVE_TRAVEL_DURATION.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.03).timeout
	assert_eq(emitted.size(), 1, "K after rotation completes should emit answer_submitted")

# --- Fade-in visibility ---

func test_display_prompt_text_body_starts_cards_transparent():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 0.0, 0.01, "text-body prompt should stage cards at alpha 0")

func test_display_prompt_image_body_starts_cards_opaque():
	var c := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	prompt.body_image = PlaceholderTexture2D.new()
	# DialoguePrompt.has_image_body() returns true when body_image is set.
	c.display_prompt(prompt)
	await get_tree().process_frame
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "image-body prompt should stage cards at alpha 1")

func test_start_fade_in_resolves_after_fade_duration():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var t_start := Time.get_ticks_msec()
	await c.start_fade_in()
	var elapsed_ms := Time.get_ticks_msec() - t_start
	var expected_ms := int(AnswerCarousel.FADE_IN_DURATION * 1000.0)
	assert_true(elapsed_ms >= expected_ms - 30, "start_fade_in should await full FADE_IN_DURATION — expected ≥%dms, got %dms" % [expected_ms - 30, elapsed_ms])
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "cards should be opaque after fade-in")

func test_display_prompt_instant_skips_fade_cards_immediately_visible():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	for card in c.get_cards():
		assert_almost_eq(card.modulate.a, 1.0, 0.01, "display_prompt_instant should show cards at full opacity immediately")

func test_jl_locked_while_fading_in():
	var c := _mount()
	c.display_prompt(_make_prompt(["r0", "r1", "r2"]))
	c.start_fade_in()  # don't await — fade in flight
	await get_tree().create_timer(AnswerCarousel.FADE_IN_DURATION * 0.4).timeout
	# Fade is in flight; any alpha in (0, 1) satisfies the check.
	assert_almost_eq(c.get_cards()[1].modulate.a, 0.5, 0.5, "still fading in (alpha somewhere in 0..1)")
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 1, "J/L must be ignored during fade-in")

# --- Confirm + exit tween ---

func test_confirm_emits_answer_submitted_with_outcome_and_picked():
	var c := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	c.display_prompt_instant(prompt)
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append([outcome, picked]))
	_send_action("menu_confirm")
	# Emit is now deferred to impact frame — wait for GLOVE_TRAVEL_DURATION.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.03).timeout
	assert_eq(emitted.size(), 1, "K should emit answer_submitted once")
	var event: Array = emitted[0]
	assert_true(event[1] is DialogueAnswer, "second arg should be the picked DialogueAnswer")
	# After shuffle, the middle card is one of the three answers; outcome matches.
	var picked_outcome: int = event[0]
	var picked: DialogueAnswer = event[1]
	assert_eq(picked_outcome, picked.outcome, "outcome arg should match picked.outcome")

func test_show_reaction_for_animates_unpicked_cards_out():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	var start_pos_0: Vector2 = cards[0].position
	var start_pos_2: Vector2 = cards[2].position
	c.show_reaction_for(1)
	await get_tree().create_timer(AnswerCarousel.EXIT_DURATION * 0.5).timeout
	assert_true(cards[0].modulate.a < 0.9, "left card alpha should be tweening down")
	assert_true(cards[2].modulate.a < 0.9, "right card alpha should be tweening down")
	assert_true(cards[0].position != start_pos_0, "left card position should be tweening toward off-screen")
	assert_true(cards[2].position != start_pos_2, "right card position should be tweening toward off-screen")

func test_show_reaction_for_locks_input():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	c.show_reaction_for(1)
	await get_tree().process_frame
	assert_eq(c.get_state(), AnswerCarousel.State.REACTION)
	_send_action("menu_right")
	await get_tree().process_frame
	assert_eq(c._highlight_index, 1, "J/L must be ignored in REACTION state")

# --- Phase 2 Task 6: diagonal layout ---

func test_side_left_anchor_is_below_and_left_of_center():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	assert_true(cards[0].position.x < cards[1].position.x, "left side card x should be < center card x")
	assert_true(cards[0].position.y > cards[1].position.y, "left side card y should be > center card y (lower on screen)")

func test_side_right_anchor_is_above_and_right_of_center():
	var c := _mount()
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var cards := c.get_cards()
	assert_true(cards[2].position.x > cards[1].position.x, "right side card x should be > center card x")
	assert_true(cards[2].position.y < cards[1].position.y, "right side card y should be < center card y (higher on screen)")

# --- Phase 3 Task 9: glove punch trigger + _is_punching gate ---

const PlayerGlovesScene_Task9 := preload("res://scenes/actors/player_gloves.tscn")

func _mount_carousel_with_gloves() -> Array:
	# Returns [carousel, gloves]. The carousel needs a gloves reference to
	# trigger the punch; tests construct both as siblings under a root.
	var root := Node.new()
	add_child_autoqfree(root)
	var gloves: PlayerGloves = PlayerGlovesScene_Task9.instantiate()
	gloves.name = "PlayerGloves"
	root.add_child(gloves)
	var c: AnswerCarousel = AnswerCarouselScene.instantiate()
	root.add_child(c)
	# Inject the gloves reference via the carousel's setter (added in this task).
	c.set_player_gloves(gloves)
	return [c, gloves]

func test_k_confirm_triggers_glove_punch_and_locks_is_punching():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	var gloves: PlayerGloves = pair[1]
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_false(c._is_punching, "_is_punching should be false before K")
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_true(c._is_punching, "_is_punching should be true after K")
	# Glove should have started traveling toward the picked card's global position.
	# RightGlove rest position is Vector2(1760, 920) per player_gloves.tscn.
	# TRANS_BACK easing moves very little in the first frame (~4px); wait a second
	# frame so the tween is well into travel before sampling the position.
	await get_tree().process_frame
	var glove_pos := (gloves.get_node("RightGlove") as Node2D).position
	assert_true(glove_pos.distance_to(Vector2(1760, 920)) > 5.0, "right glove should have started moving from rest (1760, 920)")

# --- Phase 3 Task 10: impact-frame timing ---

func test_answer_submitted_emits_at_impact_frame_not_at_k_press():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	var emitted: Array = []
	c.answer_submitted.connect(func(outcome, picked): emitted.append(Time.get_ticks_msec()))
	var t_press := Time.get_ticks_msec()
	_send_action("menu_confirm")
	await get_tree().process_frame
	assert_eq(emitted.size(), 0, "answer_submitted should NOT emit on K-press")
	# Wait for the glove to reach the card.
	await get_tree().create_timer(PlayerGloves.GLOVE_TRAVEL_DURATION + 0.03).timeout
	assert_eq(emitted.size(), 1, "answer_submitted should emit at impact frame")
	var t_emit: int = emitted[0]
	var elapsed_ms := t_emit - t_press
	var expected_ms := int(PlayerGloves.GLOVE_TRAVEL_DURATION * 1000.0)
	assert_true(elapsed_ms >= expected_ms - 30, "emit should be delayed by ~GLOVE_TRAVEL_DURATION — got %dms" % elapsed_ms)

# --- Phase 4 Task 11: card_struck_opponent signal ---

func test_card_struck_opponent_emits_after_flight_with_direction_right():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt_all(Outcome.Type.RIGHT))
	await get_tree().process_frame
	var emitted: Array = []
	c.card_struck_opponent.connect(func(direction): emitted.append(direction))
	_send_action("menu_confirm")
	# Wait through glove travel + impact + card flight (with slack).
	var total = PlayerGloves.GLOVE_TRAVEL_DURATION + AnswerCarousel.CARD_FLIGHT_DURATION + 0.05
	await get_tree().create_timer(total).timeout
	assert_eq(emitted.size(), 1, "card_struck_opponent should emit once after flight tween completes")
	# Opponent has `enum Direction { LEFT = 0, RIGHT = 1 }` — confirm RIGHT (= 1).
	assert_eq(emitted[0], 1, "direction should be Opponent.Direction.RIGHT (1) — card comes from screen-right")

# --- Per-outcome card choreography ---

func test_neutral_outcome_does_not_emit_card_struck_opponent():
	var pair := _mount_carousel_with_gloves()
	var c: AnswerCarousel = pair[0]
	c.display_prompt_instant(_make_prompt_all(Outcome.Type.NEUTRAL))
	await get_tree().process_frame
	var emitted: Array = []
	c.card_struck_opponent.connect(func(direction): emitted.append(direction))
	_send_action("menu_confirm")
	# Wait through glove travel + flight + the full rebound window so any
	# late emit would have fired by now.
	var total = PlayerGloves.GLOVE_TRAVEL_DURATION + AnswerCarousel.CARD_FLIGHT_DURATION + AnswerCarousel.CARD_REBOUND_DURATION + 0.1
	await get_tree().create_timer(total).timeout
	assert_eq(emitted.size(), 0, "card_struck_opponent must NOT emit on NEUTRAL outcome — opponent stays IDLE through the rebound")
