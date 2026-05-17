extends GutTest

const Dir := preload("res://scripts/game/simon_sequence.gd").Direction

func _seeded() -> SimonSequence:
	var seq := SimonSequence.new()
	seq.seed_rng(42)
	return seq

func test_starts_empty_then_advance_to_length_one():
	var seq := _seeded()
	assert_eq(seq.length(), 0)
	seq.extend()
	assert_eq(seq.length(), 1)

func test_extend_accumulates_preserving_prefix():
	var seq := _seeded()
	seq.extend()
	var first := seq.steps()[0]
	seq.extend()
	assert_eq(seq.length(), 2)
	assert_eq(seq.steps()[0], first, "Prefix preserved on accumulation")

func test_validate_step_at_index():
	var seq := _seeded()
	seq.extend()
	var step := seq.steps()[0]
	assert_true(seq.validate_at(0, step))
	assert_false(seq.validate_at(0, _wrong_direction(step)))

func test_reset_clears_chain():
	var seq := _seeded()
	seq.extend()
	seq.extend()
	seq.reset()
	assert_eq(seq.length(), 0)

func test_direction_set_is_complete():
	assert_eq(SimonSequence.ALL_DIRECTIONS.size(), 4)

func test_validate_at_returns_false_for_out_of_range_index():
	var seq := _seeded()
	seq.extend()
	assert_false(seq.validate_at(-1, SimonSequence.Direction.HEAD), "Negative index is invalid")
	assert_false(seq.validate_at(99, SimonSequence.Direction.HEAD), "Index past end is invalid")

func _wrong_direction(step: int) -> int:
	for d in SimonSequence.ALL_DIRECTIONS:
		if d != step:
			return d
	return step
