class_name SweatFX
extends Node2D

# Per-direction sweat burst on player-landed attacks. Each Direction owns its
# own CPUParticles2D child so overlapping finisher bursts play in parallel
# without restart() clobbering an in-flight spray.
#
# This file is the single-source tuning surface — playtest iteration is a
# constants-only edit. See docs/superpowers/specs/2026-05-24-sweat-particle-fx-design.md.

# Anchor offsets in Opponent-local coordinates. Y values are placeholder
# guesses — Task 3 verifies them against the actual sprite layout in the
# editor and snapshots the corrected values back.
const IMPACT_OFFSETS := {
	SimonSequence.Direction.HEAD:  Vector2(  0, 690),
	SimonSequence.Direction.LEFT:  Vector2(-90, 690),
	SimonSequence.Direction.BODY:  Vector2(  0, 820),
	SimonSequence.Direction.RIGHT: Vector2( 90, 690),
}

# Per-direction launch vectors. Sign convention matches
# WasdPrompt.toss_horizontal_for(): jabs (W/S) lean slightly upward in the
# matching horizontal direction, hooks (A/D) lean more horizontal.
const LAUNCH_VECTORS := {
	SimonSequence.Direction.HEAD:  Vector2(-0.5, -1.0),
	SimonSequence.Direction.LEFT:  Vector2( 1.0, -0.6),
	SimonSequence.Direction.BODY:  Vector2( 0.5, -1.0),
	SimonSequence.Direction.RIGHT: Vector2(-1.0, -0.6),
}

var _emitters: Dictionary = {}

func _ready() -> void:
	_emitters[SimonSequence.Direction.HEAD]  = get_node_or_null("Head")
	_emitters[SimonSequence.Direction.LEFT]  = get_node_or_null("Left")
	_emitters[SimonSequence.Direction.BODY]  = get_node_or_null("Body")
	_emitters[SimonSequence.Direction.RIGHT] = get_node_or_null("Right")

func emit_for(direction: int) -> void:
	var emitter: CPUParticles2D = _emitters.get(direction)
	if emitter == null:
		return
	emitter.restart()
