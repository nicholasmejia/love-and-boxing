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
	box.display(_make_prompt(["r0", "r1", "r2"]))
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)

func test_show_reaction_hides_unpicked_cards_and_swaps_body_text():
	var box := _mount()
	var prompt := _make_prompt(["r0", "r1", "r2"])
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(1)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.REACTION)
	var cards := box.get_cards()
	assert_false(cards[0].visible)
	assert_true(cards[1].visible)
	assert_false(cards[2].visible)

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
	box.display(prompt)
	await get_tree().process_frame
	box.show_reaction(2)
	await get_tree().process_frame
	box.display(prompt)
	await get_tree().process_frame
	assert_eq(box.get_state(), RiddleBox.State.NORMAL)
	for card in box.get_cards():
		assert_true(card.visible)
