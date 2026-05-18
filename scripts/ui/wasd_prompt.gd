class_name WasdPrompt
extends Control

# Variant of the per-direction WASD command sprite. PROMPT is the show-phase
# telegraph; SUCCESS flashes on a correct repeat-phase keystroke; FAIL flashes
# on a miss (wrong key or input-window timeout). Sprite files live at
# `res://assets/sprites/commands/<token>_<suffix>.png` — see CONTEXT.md for
# the full manifest.
enum Variant { PROMPT, SUCCESS, FAIL }

@onready var _label: Label = $Label
@onready var _bg: ColorRect = $Background
@onready var _image: TextureRect = $Image

# `display` rather than `show` to avoid shadowing Node.show() — callers should
# go through WasdPromptLayer.flash / flash_success / flash_fail anyway, but a
# direct override of Node.show would silently change semantics for any future
# caller that thinks it's calling the inherited method.
func display(direction: int, variant: int = Variant.PROMPT) -> void:
	var token := _token_for(direction)
	var suffix := _suffix_for(variant)
	_label.text = token.to_upper()
	var path := "res://assets/sprites/commands/%s_%s.png" % [token, suffix]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_image.texture = tex
		_image.visible = true
		_label.visible = false
		_bg.visible = false
	else:
		_image.visible = false
		_label.visible = true
		_bg.visible = true
	visible = true

func hide_prompt() -> void:
	visible = false

func _token_for(direction: int) -> String:
	match direction:
		SimonSequence.Direction.HEAD: return "w"
		SimonSequence.Direction.LEFT: return "a"
		SimonSequence.Direction.BODY: return "s"
		SimonSequence.Direction.RIGHT: return "d"
	return ""

func _suffix_for(variant: int) -> String:
	match variant:
		Variant.SUCCESS: return "success"
		Variant.FAIL: return "fail"
		_: return "prompt"
