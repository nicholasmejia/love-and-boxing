class_name AttackPhase
extends Node

signal show_started(steps: Array)
signal step_flashed(direction: int)
signal repeat_started
signal step_landed(index: int)
signal attack_succeeded
signal attack_failed(expected_direction: int)

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.5
@export var input_window_seconds: float = 3.0

var _sequence: SimonSequence = SimonSequence.new()
var _expected_index: int = 0
var _repeat_active: bool = false
var _timeout_timer: Timer
var _expected_count: int = 1
# Bumps on every begin()/stop(). _show captures this at entry and bails after
# each await when a newer call has bumped it. Mirrors DefensePhase._generation
# (see commit b89de48) — closes the same stop()+begin() race where an old
# show loop's pending awaits would resolve on top of a fresh chain.
var _generation: int = 0

func _ready() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.timeout.connect(_on_input_timeout)
	add_child(_timeout_timer)

func begin(input_count: int) -> void:
	_expected_count = input_count
	_sequence.reset()
	for i in input_count:
		_sequence.extend()
	_generation += 1
	_show()

func stop() -> void:
	_generation += 1
	_repeat_active = false
	_timeout_timer.stop()

func expected_inputs() -> int:
	return _expected_count

func current_sequence() -> SimonSequence:
	return _sequence

func _show() -> void:
	var my_gen := _generation
	await get_tree().create_timer(interlude_seconds).timeout
	if my_gen != _generation:
		return
	show_started.emit(_sequence.steps())
	for step in _sequence.steps():
		if my_gen != _generation:
			return
		step_flashed.emit(step)
		await get_tree().create_timer(step_seconds).timeout
		if my_gen != _generation:
			return
		await get_tree().create_timer(gap_seconds).timeout
	if my_gen == _generation:
		_begin_repeat()

func _begin_repeat() -> void:
	_expected_index = 0
	_repeat_active = true
	repeat_started.emit()
	_timeout_timer.start(input_window_seconds)

func player_input(direction: int) -> void:
	if not _repeat_active:
		return
	if _sequence.validate_at(_expected_index, direction):
		step_landed.emit(_expected_index)
		_expected_index += 1
		if _expected_index >= _sequence.length():
			_repeat_active = false
			_timeout_timer.stop()
			attack_succeeded.emit()
		else:
			_timeout_timer.start(input_window_seconds)
	else:
		_fail()

func _on_input_timeout() -> void:
	if _repeat_active:
		_fail()

func _fail() -> void:
	# Invariant: _fail is only reachable while _repeat_active is true, which
	# means the show phase populated _sequence and _expected_index points at
	# the missed step. Read the direction BEFORE clearing state, matching
	# DefensePhase._fail_with_damage.
	var expected_direction: int = _sequence.steps()[_expected_index]
	_repeat_active = false
	_timeout_timer.stop()
	attack_failed.emit(expected_direction)
