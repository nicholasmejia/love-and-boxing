class_name AnnouncementBanner
extends Control

const _BANNERS_DIR := "res://assets/sprites/ui/banners/"

@onready var _image: TextureRect = $CenterContainer/Image
@onready var _label: Label = $CenterContainer/Label

func _ready() -> void:
	visible = false

func show_banner(banner_name: String, duration_seconds: float) -> void:
	var path := "%sbanner_%s.png" % [_BANNERS_DIR, banner_name]
	if ResourceLoader.exists(path):
		_image.texture = load(path)
		_image.visible = true
		_label.visible = false
	else:
		_image.visible = false
		_label.text = banner_name
		_label.visible = true
	visible = true
	await get_tree().create_timer(duration_seconds).timeout
	visible = false

func show_message(message: String, duration_seconds: float) -> void:
	_image.visible = false
	_label.text = message
	_label.visible = true
	visible = true
	await get_tree().create_timer(duration_seconds).timeout
	visible = false

func show_prompt(message: String) -> void:
	_image.visible = false
	_label.text = message
	_label.visible = true
	visible = true

func dismiss() -> void:
	visible = false
