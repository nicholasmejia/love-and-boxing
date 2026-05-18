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
	var sources := _make_prompts(3)
	deck.load_prompts(sources)
	var first_cycle: Array[String] = []
	for i in 3:
		first_cycle.append(deck.draw().body_text)
	var second_cycle: Array[String] = []
	for i in 3:
		second_cycle.append(deck.draw().body_text)
	first_cycle.sort()
	second_cycle.sort()
	assert_eq(second_cycle, ["p0", "p1", "p2"], "Reshuffled deck must contain every original prompt")
	assert_eq(first_cycle, second_cycle, "Both cycles must draw the same multiset of prompts")

func test_draw_returns_null_when_no_prompts_loaded():
	var deck := DialogueDeck.new()
	assert_null(deck.draw(), "Empty deck returns null")

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
