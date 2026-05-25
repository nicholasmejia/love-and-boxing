class_name DefensePhase
extends Node

signal show_started(steps: Array)
signal show_completed
signal step_flashed(direction: int)
signal repeat_started
signal step_blocked(index: int)
signal sequence_completed
signal damage_taken(expected_direction: int)

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var input_window_seconds: float = 3.0
@export var sequence_growth: int = 1
# Breath between a completed Simon chain and the next chain's show phase. Does
# not apply to the first round after start() — the Riddle Render Gate already
# owns that breath. See CONTEXT.md → Simon Sequence.
@export var inter_round_seconds: float = 1.5

var _sequence: SimonSequence = SimonSequence.new()
var _running: bool = false
var _expected_index: int = 0
var _repeat_active: bool = false
var _timeout_timer: Timer
# Bumps on every start/stop/replay. _run_show_then_repeat captures this at
# entry and bails when a newer call has bumped it. Closes a stop()+start()
# race where the previous _running flag flip is masked by the immediate
# re-set to true, letting the old loop's awaits resolve and continue emitting
# step_flashed for the dead chain.
var _generation: int = 0

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
	_generation += 1
	_running = true
	_begin_next_round()

func stop() -> void:
	_generation += 1
	_running = false
	_repeat_active = false
	_timeout_timer.stop()

func current_steps() -> Array:
	return _sequence.steps()

func current_sequence() -> SimonSequence:
	return _sequence

func begin_repeat_phase() -> void:
	_expected_index = 0
	_repeat_active = true
	repeat_started.emit()
	_timeout_timer.start(input_window_seconds)

func player_input(direction: int) -> void:
	if not _repeat_active:
		return
	if _sequence.validate_at(_expected_index, direction):
		step_blocked.emit(_expected_index)
		_expected_index += 1
		if _expected_index >= _sequence.length():
			_repeat_active = false
			_timeout_timer.stop()
			sequence_completed.emit()
			if _running:
				_begin_next_round()
		else:
			_timeout_timer.start(input_window_seconds)
	else:
		_fail_with_damage()

func _on_input_timeout() -> void:
	if _repeat_active:
		_fail_with_damage()

func _fail_with_damage() -> void:
	# Invariant: _fail_with_damage is only reachable while _repeat_active is true,
	# which implies the show phase populated _sequence and _expected_index points at
	# the missed step. Read the direction BEFORE resetting the sequence.
	var expected_direction: int = _sequence.steps()[_expected_index]
	_repeat_active = false
	_running = false
	_timeout_timer.stop()
	damage_taken.emit(expected_direction)
	_sequence.reset()
	# No auto-continue. Gameplay's damage_taken handler owns scheduling the next
	# start() via _begin_breather_gap — the Riddle Render Gate must complete
	# before the new chain's first flash.

func replay() -> void:
	# Re-run the show phase of the current chain from step 0 without extending
	# or resetting. Used by gameplay for NEUTRAL answer's "Try again!" hint.
	assert(_sequence.length() > 0, "DefensePhase.replay called with empty sequence")
	_generation += 1
	_repeat_active = false
	_timeout_timer.stop()
	_running = true
	_run_show_then_repeat()

func _begin_next_round() -> void:
	if not _running:
		return
	var my_gen := _generation
	for _i in max(1, sequence_growth):
		_sequence.extend()
	# Subsequent rounds (length > 1) get an inter-round breath. The first round
	# after start() (length == 1) skips it — the external Riddle Render Gate
	# already owns the pre-first-show beat.
	if _sequence.length() > 1 and inter_round_seconds > 0.0:
		await get_tree().create_timer(inter_round_seconds, false).timeout
		if my_gen != _generation or not _running:
			return
	_run_show_then_repeat()

func _run_show_then_repeat() -> void:
	var my_gen := _generation
	show_started.emit(_sequence.steps())
	for step in _sequence.steps():
		if my_gen != _generation:
			return
		step_flashed.emit(step)
		await get_tree().create_timer(step_seconds, false).timeout
		if my_gen != _generation:
			return
		await get_tree().create_timer(gap_seconds, false).timeout
	show_completed.emit()
	if my_gen == _generation:
		begin_repeat_phase()
