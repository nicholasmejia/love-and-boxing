extends GutTest

func test_hearts_start_at_five():
	var h := Hearts.new()
	assert_eq(h.current(), 5)

func test_damage_subtracts_one():
	var h := Hearts.new()
	h.take_damage()
	assert_eq(h.current(), 4)

func test_damage_never_below_zero():
	var h := Hearts.new()
	for i in range(10):
		h.take_damage()
	assert_eq(h.current(), 0)

func test_heal_adds_one():
	var h := Hearts.new()
	h.take_damage()
	h.take_damage()
	h.heal()
	assert_eq(h.current(), 4)

func test_heal_caps_at_five():
	var h := Hearts.new()
	h.heal()
	assert_eq(h.current(), 5, "Heal at full health should stay at 5")

func test_is_empty():
	var h := Hearts.new()
	assert_false(h.is_empty())
	for i in range(5):
		h.take_damage()
	assert_true(h.is_empty())
