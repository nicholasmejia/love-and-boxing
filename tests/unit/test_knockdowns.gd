extends GutTest

func test_starts_at_zero():
	var k := Knockdowns.new()
	assert_eq(k.count(), 0)

func test_increment():
	var k := Knockdowns.new()
	k.increment()
	assert_eq(k.count(), 1)

func test_round_end_decrement():
	var k := Knockdowns.new()
	k.increment()
	k.increment()
	k.apply_round_end_decrement()
	assert_eq(k.count(), 1)

func test_round_end_floor_at_zero():
	var k := Knockdowns.new()
	k.apply_round_end_decrement()
	assert_eq(k.count(), 0, "Decrement at zero stays at zero")

func test_is_knockout_at_three():
	var k := Knockdowns.new()
	k.increment()
	k.increment()
	assert_false(k.is_knockout())
	k.increment()
	assert_true(k.is_knockout())
