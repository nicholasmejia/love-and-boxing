extends GutTest

func _make_prompt(label: String) -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = label
	return p

func _make_prompts(count: int) -> Array[DialoguePrompt]:
	var arr: Array[DialoguePrompt] = []
	for i in count:
		arr.append(_make_prompt("p%d" % i))
	return arr

func test_draws_each_prompt_once_before_repeating():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_prompts(_make_prompts(4))
	var drawn: Array[String] = []
	for i in 4:
		drawn.append(deck.draw().body_text)
	drawn.sort()
	assert_eq(drawn, ["p0", "p1", "p2", "p3"])

func test_reshuffles_after_exhaustion():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_prompts(_make_prompts(2))
	deck.draw()
	deck.draw()
	var fifth := deck.draw()
	assert_not_null(fifth, "Deck must reshuffle after exhausting")

func test_reset_reshuffles_full_deck():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_prompts(_make_prompts(3))
	deck.draw()
	deck.reset()
	var drawn: Array[String] = []
	for i in 3:
		drawn.append(deck.draw().body_text)
	drawn.sort()
	assert_eq(drawn, ["p0", "p1", "p2"], "Reset restores all prompts")
