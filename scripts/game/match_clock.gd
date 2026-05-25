class_name MatchClock
extends RefCounted

const ROUND_DURATION_SECONDS := 180.0
const TOTAL_ROUNDS := 2

var _seconds_remaining: float = ROUND_DURATION_SECONDS
var _current_round: int = 1
var _running: bool = false
var _match_over: bool = false

func start() -> void:
	_running = true

func pause() -> void:
	_running = false

func resume() -> void:
	_running = true

func tick(delta: float) -> void:
	if not _running or _match_over:
		return
	_seconds_remaining = max(0.0, _seconds_remaining - delta)

func seconds_remaining() -> float:
	return _seconds_remaining

func current_round() -> int:
	return _current_round

func is_round_over() -> bool:
	return _seconds_remaining <= 0.0

func is_match_over() -> bool:
	return _match_over or (is_round_over() and _current_round >= TOTAL_ROUNDS)

func advance_to_next_round() -> void:
	if _current_round >= TOTAL_ROUNDS:
		_match_over = true
		return
	_current_round += 1
	_seconds_remaining = ROUND_DURATION_SECONDS
