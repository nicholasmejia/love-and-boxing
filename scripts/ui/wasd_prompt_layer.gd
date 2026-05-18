class_name WasdPromptLayer
extends Control

@onready var _prompts: Dictionary = {
	SimonSequence.Direction.HEAD: $Head,
	SimonSequence.Direction.LEFT: $Left,
	SimonSequence.Direction.BODY: $Body,
	SimonSequence.Direction.RIGHT: $Right,
}

func _ready() -> void:
	hide_all()

func flash(direction: int, duration_seconds: float) -> void:
	var prompt: WasdPrompt = _prompts[direction]
	prompt.show_direction(direction)
	await get_tree().create_timer(duration_seconds).timeout
	prompt.hide_prompt()

func hide_all() -> void:
	for p in _prompts.values():
		p.hide_prompt()
