class_name SimonSequence
extends RefCounted

enum Direction {
	HEAD = 0,    # W
	LEFT = 1,    # A (left hook)
	BODY = 2,    # S
	RIGHT = 3,   # D (right hook)
}

const ALL_DIRECTIONS: Array[int] = [
	Direction.HEAD,
	Direction.LEFT,
	Direction.BODY,
	Direction.RIGHT,
]

var _steps: Array[int] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

func length() -> int:
	return _steps.size()

func steps() -> Array[int]:
	return _steps.duplicate()

func extend() -> void:
	var next := ALL_DIRECTIONS[_rng.randi() % ALL_DIRECTIONS.size()]
	_steps.append(next)

func validate_at(index: int, direction: int) -> bool:
	if index < 0 or index >= _steps.size():
		return false
	return _steps[index] == direction

func reset() -> void:
	_steps.clear()
