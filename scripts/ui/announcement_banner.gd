class_name AnnouncementBanner
extends Control

@onready var _label: Label = $CenterContainer/Label

func _ready() -> void:
	visible = false

func show_message(message: String, duration_seconds: float) -> void:
	_label.text = message
	visible = true
	await get_tree().create_timer(duration_seconds).timeout
	visible = false
