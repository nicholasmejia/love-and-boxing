class_name DialogueDeck
extends RefCounted

const TIER_COUNT := 3

var _source: Array = [[], [], []]
var _remaining: Array = [[], [], []]
var _active_tier: int = 0
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

func load_tier(tier: int, prompts: Array[DialoguePrompt]) -> void:
	var idx := _clamp_tier(tier)
	_source[idx] = prompts.duplicate()
	_remaining[idx] = prompts.duplicate()

func set_active_tier(tier: int) -> void:
	_active_tier = _clamp_tier(tier)

func draw() -> DialoguePrompt:
	var pool: Array = _remaining[_active_tier]
	if pool.is_empty():
		_refill(_active_tier)
		pool = _remaining[_active_tier]
	if pool.is_empty():
		return null
	var idx := _rng.randi() % pool.size()
	return pool.pop_at(idx)

func reset() -> void:
	for tier in range(TIER_COUNT):
		_refill(tier)

func _refill(tier: int) -> void:
	_remaining[tier] = (_source[tier] as Array).duplicate()

func _clamp_tier(tier: int) -> int:
	return clamp(tier, 0, TIER_COUNT - 1)
