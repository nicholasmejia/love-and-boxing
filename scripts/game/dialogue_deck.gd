class_name DialogueDeck
extends RefCounted

var _source: Array[DialoguePrompt] = []
var _remaining: Array[DialoguePrompt] = []
var _rng := RandomNumberGenerator.new()

func _init() -> void:
	_rng.randomize()

func seed_rng(seed_value: int) -> void:
	_rng.seed = seed_value

func load_prompts(prompts: Array[DialoguePrompt]) -> void:
	_source = prompts.duplicate()
	_refill()

func draw() -> DialoguePrompt:
	if _remaining.is_empty():
		_refill()
	if _remaining.is_empty():
		return null
	var idx := _rng.randi() % _remaining.size()
	return _remaining.pop_at(idx)

func reset() -> void:
	_refill()

func _refill() -> void:
	_remaining = _source.duplicate()
