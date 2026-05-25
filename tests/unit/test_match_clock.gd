extends GutTest

func test_starts_at_full_round():
	var c := MatchClock.new()
	assert_eq(c.seconds_remaining(), MatchClock.ROUND_DURATION_SECONDS)
	assert_eq(c.current_round(), 1)

func test_tick_decrements_when_running():
	var c := MatchClock.new()
	c.start()
	c.tick(1.5)
	assert_almost_eq(c.seconds_remaining(), MatchClock.ROUND_DURATION_SECONDS - 1.5, 0.001)

func test_pause_freezes_clock():
	var c := MatchClock.new()
	c.start()
	c.pause()
	c.tick(5.0)
	assert_eq(c.seconds_remaining(), MatchClock.ROUND_DURATION_SECONDS)

func test_resume_unfreezes_clock():
	var c := MatchClock.new()
	c.start()
	c.pause()
	c.tick(5.0)
	c.resume()
	c.tick(1.0)
	assert_almost_eq(c.seconds_remaining(), MatchClock.ROUND_DURATION_SECONDS - 1.0, 0.001)

func test_round_over_when_zero():
	var c := MatchClock.new()
	c.start()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	assert_true(c.is_round_over())

func test_advance_round_resets_clock():
	var c := MatchClock.new()
	c.start()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	c.advance_to_next_round()
	assert_eq(c.current_round(), 2)
	assert_eq(c.seconds_remaining(), MatchClock.ROUND_DURATION_SECONDS)

func test_no_third_round():
	var c := MatchClock.new()
	c.start()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	c.advance_to_next_round()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	assert_true(c.is_match_over())

func test_advance_after_match_end_is_idempotent():
	var c := MatchClock.new()
	c.start()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	c.advance_to_next_round()
	c.tick(MatchClock.ROUND_DURATION_SECONDS)
	c.advance_to_next_round()
	c.advance_to_next_round()
	assert_eq(c.current_round(), 2, "Round should not advance past round 2")
	assert_true(c.is_match_over())
