class_name AnnouncementBanner
extends Control

const _BANNERS_DIR := "res://assets/sprites/ui/banners/"
const _BANNER_SCALE := 0.5

# Slide + opacity tuning. The banner enters from the left at opacity 0, slides
# rightward to its rest position at opacity 1.0, holds, then continues sliding
# rightward off-rest while fading back to 0 — both transitions move in the
# same direction so the banner "passes through" its rest pose.
const _SLIDE_OFFSET_X := 120.0
const _IN_DURATION := 0.25
const _OUT_DURATION := 0.20

@onready var _backdrop: ColorRect = $Backdrop
@onready var _center: CenterContainer = $CenterContainer
@onready var _image: TextureRect = $CenterContainer/Image
@onready var _label: Label = $CenterContainer/Label

# CenterContainer re-centers its child every layout pass, so tweening the
# AnnouncementBanner root's position fights the layout. The CenterContainer
# fills the screen via anchors, so its own position.x can slide freely without
# affecting its child's centering — animating that is the slide vehicle.
var _center_rest_x: float = 0.0
var _active_tween: Tween

func _ready() -> void:
	visible = false
	_center_rest_x = _center.position.x

# Total wall-clock time a banner occupies for the given hold. Used by callers
# that subtract a banner from a larger pause budget (e.g., KNOCKDOWN_PAUSE).
static func total_duration_for(hold_seconds: float) -> float:
	return _IN_DURATION + hold_seconds + _OUT_DURATION

func show_banner(banner_name: String, duration_seconds: float) -> void:
	_apply_banner_image(banner_name)
	await _animate_in()
	await get_tree().create_timer(duration_seconds).timeout
	await _animate_out()

# Same as show_banner, but the hold races a skip Signal — whichever fires
# first wins, then the slide-out plays. Used for the YOU_WIN / YOU_LOSE
# banners so the player can press K to bail before the (long) stinger
# track finishes.
func show_banner_skippable(banner_name: String, max_seconds: float, skipper: Signal) -> void:
	_apply_banner_image(banner_name)
	await _animate_in()
	await _await_first(get_tree().create_timer(max_seconds).timeout, skipper)
	await _animate_out()

func _apply_banner_image(banner_name: String) -> void:
	var path := "%sbanner_%s.png" % [_BANNERS_DIR, banner_name]
	if ResourceLoader.exists(path):
		_image.texture = load(path)
		_image.custom_minimum_size = _image.texture.get_size() * _BANNER_SCALE
		_image.visible = true
		_label.visible = false
	else:
		_image.visible = false
		_label.text = banner_name
		_label.visible = true

func _await_first(sig_a: Signal, sig_b: Signal) -> void:
	var done := [false]
	var on_fire := func():
		done[0] = true
	sig_a.connect(on_fire, CONNECT_ONE_SHOT)
	sig_b.connect(on_fire, CONNECT_ONE_SHOT)
	while not done[0]:
		await get_tree().process_frame
	if sig_a.is_connected(on_fire):
		sig_a.disconnect(on_fire)
	if sig_b.is_connected(on_fire):
		sig_b.disconnect(on_fire)

func show_prompt(message: String) -> void:
	_image.visible = false
	_label.text = message
	_label.visible = true
	await _animate_in()

func dismiss() -> void:
	if not visible:
		return
	await _animate_out()

func _animate_in() -> void:
	_kill_active_tween()
	_center.position.x = _center_rest_x - _SLIDE_OFFSET_X
	modulate.a = 0.0
	visible = true
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_center, "position:x", _center_rest_x, _IN_DURATION)
	_active_tween.tween_property(self, "modulate:a", 1.0, _IN_DURATION)
	await _active_tween.finished

func _animate_out() -> void:
	_kill_active_tween()
	_active_tween = create_tween().set_parallel(true)
	_active_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_active_tween.tween_property(_center, "position:x", _center_rest_x + _SLIDE_OFFSET_X, _OUT_DURATION)
	_active_tween.tween_property(self, "modulate:a", 0.0, _OUT_DURATION)
	await _active_tween.finished
	visible = false
	modulate.a = 1.0
	_center.position.x = _center_rest_x

func _kill_active_tween() -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
