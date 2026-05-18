extends GutTest

func test_starts_at_x1():
	var c := ComboState.new()
	assert_eq(c.level(), 1)

func test_input_count_equals_level():
	var c := ComboState.new()
	assert_eq(c.input_count(), 1)
	c.on_attack_success()
	assert_eq(c.input_count(), 2)

func test_advance_through_levels():
	var c := ComboState.new()
	c.on_attack_success()
	assert_eq(c.level(), 2)
	c.on_attack_success()
	assert_eq(c.level(), 3)

func test_attack_at_x3_signals_knockdown():
	var c := ComboState.new()
	c.on_attack_success()
	c.on_attack_success()
	assert_true(c.is_at_knockdown_threshold())

func test_knockdown_resets_to_x1():
	var c := ComboState.new()
	c.on_attack_success()
	c.on_attack_success()
	c.on_knockdown_completed()
	assert_eq(c.level(), 1)

func test_damage_resets_to_x1():
	var c := ComboState.new()
	c.on_attack_success()
	c.on_damage_taken()
	assert_eq(c.level(), 1)

func test_attack_failure_does_not_reset():
	var c := ComboState.new()
	c.on_attack_success()
	c.on_attack_failure()
	assert_eq(c.level(), 2, "Failed attack must preserve combo")
