class_name WasdPromptLayer
extends Control

@onready var _prompts: Dictionary = {
	SimonSequence.Direction.HEAD: $Head,
	SimonSequence.Direction.LEFT: $Left,
	SimonSequence.Direction.BODY: $Body,
	SimonSequence.Direction.RIGHT: $Right,
}

const _PROMPT_SFX_KEYS := {
	SimonSequence.Direction.HEAD: "prompt-display-W",
	SimonSequence.Direction.LEFT: "prompt-display-A",
	SimonSequence.Direction.BODY: "prompt-display-S",
	SimonSequence.Direction.RIGHT: "prompt-display-D",
}

func _ready() -> void:
	hide_all()

func flash(direction: int, duration_seconds: float) -> void:
	if _PROMPT_SFX_KEYS.has(direction):
		AudioBus.play_sfx(_PROMPT_SFX_KEYS[direction])
	_flash_variant(direction, duration_seconds, WasdPrompt.Variant.PROMPT)

# `attack: false` (default) = defense flow → SUCCESS / FAIL variants.
# `attack: true` = attack flow → SUCCESS_ATTACK / FAIL_ATTACK variants.
# The sprite suffix is identical (success/fail) — the variant only changes
# which animation the prompt plays. Defense and attack pass through here so
# the caller in gameplay.gd stays oblivious to the variant split.
func flash_success(direction: int, duration_seconds: float, attack: bool = false) -> void:
	var variant := WasdPrompt.Variant.SUCCESS_ATTACK if attack else WasdPrompt.Variant.SUCCESS
	_flash_variant(direction, duration_seconds, variant)

func flash_fail(direction: int, duration_seconds: float, attack: bool = false) -> void:
	var variant := WasdPrompt.Variant.FAIL_ATTACK if attack else WasdPrompt.Variant.FAIL
	_flash_variant(direction, duration_seconds, variant)

func hide_all() -> void:
	for p in _prompts.values():
		p.hide_prompt()

# Screen-space center of the per-direction prompt slot. Used by DamageEffect
# to position the player_hit splat over the missed input. Returns
# Vector2.ZERO for unknown directions (the splat is suppressed in that case).
#
# Note: WasdPrompt._ready sets `pivot_offset = size / 2.0` so scale/rotation
# anchor at the visible center. In Godot 4 that pivot is folded into the
# global transform, so `global_position` already reports the visual center
# of these prompts — not the top-left. Don't add `size / 2` here; it would
# double-count the offset and place the splat at the bottom-right corner.
func prompt_center_global(direction: int) -> Vector2:
	if not _prompts.has(direction):
		return Vector2.ZERO
	var p: Control = _prompts[direction]
	return p.global_position

# Fire-and-forget — the prompt owns its own timing now (display() awaits the
# variant's tween chain and hides itself when it lands). The layer's flash
# methods used to gate the hide via an external get_tree timer; that's gone.
func _flash_variant(direction: int, duration_seconds: float, variant: int) -> void:
	var prompt: WasdPrompt = _prompts[direction]
	prompt.display(direction, variant, duration_seconds)
