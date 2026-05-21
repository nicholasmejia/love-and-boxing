extends Node

const MUSIC_TRACKS := {
	"menu": preload("res://assets/audio/bgm/menu.ogg"),
	"victory": preload("res://assets/audio/bgm/victory.ogg"),
	"defeat": preload("res://assets/audio/bgm/defeat.ogg"),
}

const SILENT_DB := -80.0

var _players: Array[AudioStreamPlayer] = []
var _active_index: int = 0
var _current_track_id: String = ""
var _fade_in_tween: Tween = null
var _fade_out_tween: Tween = null

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_players.append(p)

func play_music(name: String, crossfade_seconds: float = 0.0) -> void:
	if not MUSIC_TRACKS.has(name):
		push_warning("[AudioBus] Unknown music track: %s" % name)
		return
	_play_stream(MUSIC_TRACKS[name], name, crossfade_seconds)

func play_music_stream(stream: AudioStream, id: String, crossfade_seconds: float = 0.0) -> void:
	if stream == null:
		push_warning("[AudioBus] play_music_stream called with null stream (id=%s)" % id)
		return
	_play_stream(stream, id, crossfade_seconds)

func stop_music(fade_seconds: float = 0.0) -> void:
	if _current_track_id == "":
		return
	var active: AudioStreamPlayer = _players[_active_index]
	_current_track_id = ""
	_kill_tweens()
	if fade_seconds <= 0.0:
		active.stop()
		return
	_fade_out_tween = create_tween()
	_fade_out_tween.tween_property(active, "volume_db", SILENT_DB, fade_seconds)
	_fade_out_tween.tween_callback(active.stop)

func play_sfx(name: String) -> void:
	# Stubbed — SFX wiring is a follow-up branch.
	print("[AudioBus] play_sfx: %s" % name)

func _play_stream(stream: AudioStream, id: String, crossfade_seconds: float) -> void:
	if id == _current_track_id and _players[_active_index].playing:
		return
	_kill_tweens()
	var outgoing: AudioStreamPlayer = _players[_active_index]
	var incoming: AudioStreamPlayer = _players[1 - _active_index]
	_active_index = 1 - _active_index
	_current_track_id = id
	incoming.stream = stream
	if crossfade_seconds <= 0.0:
		outgoing.stop()
		incoming.volume_db = 0.0
		incoming.play()
		return
	incoming.volume_db = SILENT_DB
	incoming.play()
	_fade_in_tween = create_tween()
	_fade_in_tween.tween_property(incoming, "volume_db", 0.0, crossfade_seconds)
	if outgoing.playing:
		_fade_out_tween = create_tween()
		_fade_out_tween.tween_property(outgoing, "volume_db", SILENT_DB, crossfade_seconds)
		_fade_out_tween.tween_callback(outgoing.stop)

func _kill_tweens() -> void:
	if _fade_in_tween != null and _fade_in_tween.is_valid():
		_fade_in_tween.kill()
	if _fade_out_tween != null and _fade_out_tween.is_valid():
		_fade_out_tween.kill()
