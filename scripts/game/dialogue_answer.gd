class_name DialogueAnswer
extends Resource

@export var text: String = ""
@export var image: Texture2D
@export var outcome: int = Outcome.Type.NEUTRAL
@export var reaction_text: String = ""

func has_text() -> bool:
	return text != ""

func has_image() -> bool:
	return image != null

func has_reaction() -> bool:
	return reaction_text != ""
