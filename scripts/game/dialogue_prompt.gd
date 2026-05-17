class_name DialoguePrompt
extends Resource

@export var body_text: String = ""
@export var body_image: Texture2D
@export var answers: Array[DialogueAnswer] = []

func has_text_body() -> bool:
	return body_text != ""

func has_image_body() -> bool:
	return body_image != null
