class_name DefensePhase
extends Node

signal show_started(steps: Array)
signal show_completed
signal step_flashed(direction: int)

@export var step_seconds: float = 0.8
@export var gap_seconds: float = 0.25
@export var interlude_seconds: float = 0.6

var _sequence: SimonSequence = SimonSequence.new()
var _running: bool = false

func start() -> void:
	_sequence.reset()
	_running = true
	_next_round()

func stop() -> void:
	_running = false

func current_steps() -> Array:
	return _sequence.steps()

func _next_round() -> void:
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
		_next_round()  # First-pass loop: skip repeat phase, just keep showing.
