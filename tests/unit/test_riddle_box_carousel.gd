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
