class_name Hearts
extends RefCounted

const MAX_HEARTS := 5

var _current: int = MAX_HEARTS

func current() -> int:
	return _current

func take_damage(amount: int = 1) -> void:
	_current = max(0, _current - amount)

func heal() -> void:
	_current = min(MAX_HEARTS, _current + 1)

func is_empty() -> bool:
	return _current <= 0
