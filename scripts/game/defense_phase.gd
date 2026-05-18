class_name DefensePhase
extends Node

signal show_started(steps: Array)
signal show_completed
signal step_flashed(direction: int)
signal repeat_started
signal step_blocked(index: int)
signal sequence_completed
signal damage_taken

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.6
@export var input_window_seconds: float = 3.0

var _sequence: SimonSequence = SimonSequence.new()
var _running: bool = false
var _expected_index: int = 0
var _repeat_active: bool = false
var _timeout_timer: Timer

func _ready() -> void:
	_timeout_timer = Timer.new()
	_timeout_timer.one_shot = true
	_timeout_timer.timeout.connect(_on_input_timeout)
	add_child(_timeout_timer)

func start() -> void:
	# Listeners of step_flashed assume the previous step's await (also step_seconds long)
	# resolves inside the subsequent gap_seconds window. Guard against a misconfigured
	# step_seconds <= 0 that would collapse that assumption.
	assert(step_seconds > 0.0, "DefensePhase.step_seconds must be > 0")
	_sequence.reset()
	_running = true
	_begin_next_round()

func stop() -> void:
	_running = false
	_repeat_active = false
	if _timeout_timer:
		_timeout_timer.stop()

func current_steps() -> Array:
	return _sequence.steps()

func current_sequence() -> SimonSequence:
	return _sequence

func begin_repeat_phase() -> void:
	_expected_index = 0
	_repeat_active = true
	repeat_started.emit()
	if _timeout_timer:
		_timeout_timer.start(input_window_seconds)

func player_input(direction: int) -> void:
	if not _repeat_active:
		return
	if _sequence.validate_at(_expected_index, direction):
		step_blocked.emit(_expected_index)
		_expected_index += 1
		if _expected_index >= _sequence.length():
			_repeat_active = false
			if _timeout_timer:
				_timeout_timer.stop()
			sequence_completed.emit()
			if _running:
				_begin_next_round()
		else:
			if _timeout_timer:
				_timeout_timer.start(input_window_seconds)
	else:
		_fail_with_damage()

func _on_input_timeout() -> void:
	if _repeat_active:
		_fail_with_damage()

func _fail_with_damage() -> void:
	_repeat_active = false
	if _timeout_timer:
		_timeout_timer.stop()
	damage_taken.emit()
	_sequence.reset()
	if _running:
		_begin_next_round()

func _begin_next_round() -> void:
	if not _running:
		return
	_sequence.extend()
	await get_tree().create_timer(interlude_seconds).timeout
	if not _running:
		return
	show_started.emit(_sequence.steps())
	for step in _sequence.steps():
		if not _running:
			return
		step_flashed.emit(step)
		await get_tree().create_timer(step_seconds).timeout
		if not _running:
			return
		await get_tree().create_timer(gap_seconds).timeout
	show_completed.emit()
	if _running:
		begin_repeat_phase()
