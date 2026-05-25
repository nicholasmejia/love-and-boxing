extends GutTest

const WasdPromptLayerScene := preload("res://scenes/ui/wasd_prompt_layer.tscn")

func _mount() -> WasdPromptLayer:
	var layer: WasdPromptLayer = WasdPromptLayerScene.instantiate()
	add_child_autoqfree(layer)
	return layer

func test_prompt_center_global_returns_geometric_center_of_each_slot():
	# Locks the screen-space anchor DamageEffect uses to position the
	# player_hit splat. Offsets come from scenes/ui/wasd_prompt_layer.tscn —
	# 188×188 prompt boxes at fixed positions per direction.
	# `assert_almost_eq` because WasdPrompt sets `pivot_offset = size/2` in
	# _ready, which Godot 4 folds into the global transform with sub-pixel
	# rounding (we see e.g. 199.9991 instead of 200.0).
	var layer := _mount()
	await get_tree().process_frame
	await get_tree().process_frame
	# Head: offset 866-1054, 106-294 → center (960, 200)
	assert_almost_eq(layer.prompt_center_global(SimonSequence.Direction.HEAD), Vector2(960, 200), Vector2(0.01, 0.01))
	# Left: offset 466-654, 366-554 → center (560, 460)
	assert_almost_eq(layer.prompt_center_global(SimonSequence.Direction.LEFT), Vector2(560, 460), Vector2(0.01, 0.01))
	# Body: offset 866-1054, 366-554 → center (960, 460)
	assert_almost_eq(layer.prompt_center_global(SimonSequence.Direction.BODY), Vector2(960, 460), Vector2(0.01, 0.01))
	# Right: offset 1266-1454, 366-554 → center (1360, 460)
	assert_almost_eq(layer.prompt_center_global(SimonSequence.Direction.RIGHT), Vector2(1360, 460), Vector2(0.01, 0.01))

func test_prompt_center_global_returns_zero_for_unknown_direction():
	# DamageEffect treats Vector2.ZERO as "suppress the splat" — the helper
	# must return ZERO (not crash, not return a stale position) when handed
	# a direction that isn't mapped.
	var layer := _mount()
	await get_tree().process_frame
	assert_eq(layer.prompt_center_global(-1), Vector2.ZERO)
	assert_eq(layer.prompt_center_global(999), Vector2.ZERO)
