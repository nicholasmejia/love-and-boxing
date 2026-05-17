class_name Knockdowns
extends RefCounted

const KO_THRESHOLD := 3

var _count: int = 0

func count() -> int:
	return _count

func increment() -> void:
	_count += 1

func apply_round_end_decrement() -> void:
	_count = max(0, _count - 1)

func is_knockout() -> bool:
	return _count >= KO_THRESHOLD
