extends GutTest

func test_prompt_holds_three_answers():
	var p := DialoguePrompt.new()
	var a1 := DialogueAnswer.new()
	a1.outcome = Outcome.Type.WRONG
	a1.text = "wrong"
	var a2 := DialogueAnswer.new()
	a2.outcome = Outcome.Type.NEUTRAL
	a2.text = "neutral"
	var a3 := DialogueAnswer.new()
	a3.outcome = Outcome.Type.RIGHT
	a3.text = "right"
	p.answers = [a1, a2, a3]
	assert_eq(p.answers.size(), 3)
	assert_eq(p.answers[2].outcome, Outcome.Type.RIGHT)

func test_prompt_body_is_text_or_image():
	var p := DialoguePrompt.new()
	p.body_text = "Hello"
	assert_true(p.has_text_body())
	assert_false(p.has_image_body())

func test_prompt_with_image_body():
	var p := DialoguePrompt.new()
	p.body_image = PlaceholderTexture2D.new()
	assert_true(p.has_image_body())
	assert_false(p.has_text_body())
