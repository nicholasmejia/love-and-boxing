extends GutTest

func _make_prompt(label: String) -> DialoguePrompt:
	var p := DialoguePrompt.new()
	p.body_text = label
	return p

func _make_tier(prefix: String, count: int) -> Array[DialoguePrompt]:
	var arr: Array[DialoguePrompt] = []
	for i in count:
		arr.append(_make_prompt("%s%d" % [prefix, i]))
	return arr

func test_draw_returns_null_when_no_tiers_loaded():
	var deck := DialogueDeck.new()
	assert_null(deck.draw(), "Empty deck returns null")

func test_draws_only_from_active_tier():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_tier(0, _make_tier("a", 3))
	deck.load_tier(1, _make_tier("b", 3))
	deck.load_tier(2, _make_tier("c", 3))
	deck.set_active_tier(1)
	var drawn: Array[String] = []
	for i in 3:
		drawn.append(deck.draw().body_text)
	drawn.sort()
	assert_eq(drawn, ["b0", "b1", "b2"], "Active tier 1 yields only b-prefixed prompts")

func test_active_tier_refills_in_place_without_spillover():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_tier(0, _make_tier("a", 3))
	deck.load_tier(1, _make_tier("b", 3))
	deck.set_active_tier(0)
	# Exhaust tier 0
	for i in 3:
		deck.draw()
	# Draw three more — should refill tier 0, not spill into tier 1
	var second_cycle: Array[String] = []
	for i in 3:
		second_cycle.append(deck.draw().body_text)
	second_cycle.sort()
	assert_eq(second_cycle, ["a0", "a1", "a2"], "Refilled tier 0 contains its own prompts")

func test_set_active_tier_swaps_pool_mid_session():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_tier(0, _make_tier("a", 3))
	deck.load_tier(1, _make_tier("b", 3))
	deck.set_active_tier(0)
	deck.draw()  # consume one from tier 0
	deck.set_active_tier(1)
	var from_tier_one: Array[String] = []
	for i in 3:
		from_tier_one.append(deck.draw().body_text)
	from_tier_one.sort()
	assert_eq(from_tier_one, ["b0", "b1", "b2"], "After swap, draws come from new tier in full")

func test_set_active_tier_clamps_out_of_range():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_tier(0, _make_tier("a", 2))
	deck.load_tier(2, _make_tier("c", 2))
	deck.set_active_tier(-1)
	assert_eq(deck.draw().body_text.left(1), "a", "Negative tier clamps to 0")
	deck.set_active_tier(5)
	assert_eq(deck.draw().body_text.left(1), "c", "Tier above max clamps to 2")

func test_reset_reshuffles_all_tiers():
	var deck := DialogueDeck.new()
	deck.seed_rng(7)
	deck.load_tier(0, _make_tier("a", 3))
	deck.load_tier(1, _make_tier("b", 3))
	deck.set_active_tier(0)
	deck.draw()
	deck.set_active_tier(1)
	deck.draw()
	deck.reset()
	deck.set_active_tier(0)
	var tier_0: Array[String] = []
	for i in 3:
		tier_0.append(deck.draw().body_text)
	tier_0.sort()
	assert_eq(tier_0, ["a0", "a1", "a2"], "Reset restores tier 0 in full")
	deck.set_active_tier(1)
	var tier_1: Array[String] = []
	for i in 3:
		tier_1.append(deck.draw().body_text)
	tier_1.sort()
	assert_eq(tier_1, ["b0", "b1", "b2"], "Reset restores tier 1 in full")

func test_minty_deck_loads_with_six_prompts_per_tier_and_reactions():
	var deck := load("res://data/dialogue/minty/deck.tres") as DialogueDeckResource
	assert_not_null(deck, "minty deck failed to load")
	assert_eq(deck.tier_0.size(), 6)
	assert_eq(deck.tier_1.size(), 6)
	assert_eq(deck.tier_2.size(), 6)
	for tier in [deck.tier_0, deck.tier_1, deck.tier_2]:
		for prompt in tier:
			assert_eq(prompt.answers.size(), 3)
			assert_true(prompt.has_text_body(), "minty body should be text")
			for answer in prompt.answers:
				assert_ne(answer.text, "", "minty answer text must be set")
				assert_true(answer.has_reaction(), "minty answer reaction must be set")
