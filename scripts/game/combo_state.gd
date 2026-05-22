class_name ComboState
extends RefCounted

const MIN_LEVEL := 1
const KNOCKDOWN_LEVEL := 3

var _level: int = MIN_LEVEL
var _input_step: int = 1

func level() -> int:
	return _level

func set_input_step(step: int) -> void:
	_input_step = max(1, step)

func input_count() -> int:
	return 1 + _input_step * (_level - 1)

func is_at_knockdown_threshold() -> bool:
	return _level >= KNOCKDOWN_LEVEL

func on_attack_success() -> void:
	if _level < KNOCKDOWN_LEVEL:
		_level += 1

func on_attack_failure() -> void:
	pass  # Intentional no-op; failed attacks preserve combo.

func on_damage_taken() -> void:
	_level = MIN_LEVEL

func on_knockdown_completed() -> void:
	_level = MIN_LEVEL
