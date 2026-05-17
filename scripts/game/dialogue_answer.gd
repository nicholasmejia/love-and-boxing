class_name DialogueAnswer
extends Resource

@export var text: String = ""
@export var image: Texture2D
@export var outcome: int = Outcome.Type.NEUTRAL

func has_text() -> bool:
	return text != ""

func has_image() -> bool:
	return image != null
