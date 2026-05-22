extends Node

const MUSIC_TRACKS := {
	"menu": preload("res://assets/audio/bgm/menu.ogg"),
	"victory": preload("res://assets/audio/bgm/victory.ogg"),
	"defeat": preload("res://assets/audio/bgm/defeat.ogg"),
	"title_intro": preload("res://assets/audio/bgm/title_intro.ogg"),
	"title_main_loop": preload("res://assets/audio/bgm/title_main_loop.ogg"),
}

const SILENT_DB := -80.0

const SFX_DIR := "res://assets/audio/sfx/"
# 16 voices: a worst-case 3-hit combo layers 3 × (combo_success_N + opponent_punch_body
# + swing) = 9, plus a concurrent player_block_or_hit + input_failure + combo_reset.
const SFX_POLYPHONY := 16

# Static manifest of SFX filenames. Hardcoded instead of DirAccess-scanning because
# DirAccess.list_dir_begin() returns empty inside the packed PCK on the web export,
# which left _sfx_streams empty and all play_sfx calls silently no-op'ing in-browser.
# load(res://…) resolves through ResourceLoader and works on every platform.
const SFX_FILES: PackedStringArray = [
	"combo_reset.wav",
	"combo_success_1_hit.wav",
	"combo_success_2_hit.wav",
	"combo_success_3_hit.wav",
	"input_failure.wav",
	"menu_change_item.wav",
	"menu_option_select.wav",
	"opponent_punch_body_01.wav",
	"opponent_punch_body_02.wav",
	"opponent_punch_body_03.wav",
	"opponent_punch_body_04.wav",
	"opponent_punch_body_05.wav",
	"opponent_punch_body_06.wav",
	"opponent_punch_body_07.wav",
	"opponent_punch_body_08.wav",
	"opponent_punch_body_09.wav",
	"opponent_punch_body_10.wav",
	"player_block_or_hit_01.wav",
	"player_block_or_hit_02.wav",
	"player_block_or_hit_03.wav",
	"player_block_or_hit_04.wav",
	"riddle_correct.wav",
	"riddle_neutral.wav",
	"riddle_wrong.wav",
	"round_end.wav",
	"round_knockout.wav",
	"round_start.wav",
	"swing_01.wav",
	"swing_02.wav",
	"swing_03.wav",
	"swing_04.wav",
	"swing_05.wav",
	"swing_06.wav",
]

var _players: Array[AudioStreamPlayer] = []
var _active_index: int = 0
var _current_track_id: String = ""
var _fade_in_tween: Tween = null
var _fade_out_tween: Tween = null

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_next_index: int = 0
# Base key (e.g. "opponent_punch_body") -> Array of AudioStreams. Single-file keys
# (e.g. "combo_reset") get a one-entry Array; variant pools (filenames ending in
# "_NN") collapse to the same key and play_sfx picks one at random.
var _sfx_streams: Dictionary = {}

func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_players.append(p)
	_init_sfx_pool()
	_build_sfx_index()

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
	if not _sfx_streams.has(name):
		push_warning("[AudioBus] Unknown SFX key: %s" % name)
		return
	var pool: Array = _sfx_streams[name]
	var stream: AudioStream = pool.pick_random()
	var player: AudioStreamPlayer = _sfx_pool[_sfx_next_index]
	_sfx_next_index = (_sfx_next_index + 1) % _sfx_pool.size()
	player.stop()
	player.stream = stream
	player.play()

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

func _init_sfx_pool() -> void:
	for i in SFX_POLYPHONY:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_pool.append(p)

func _build_sfx_index() -> void:
	for fname in SFX_FILES:
		var key := _sfx_key_from_filename(fname.get_basename())
		var stream := load(SFX_DIR.path_join(fname)) as AudioStream
		if stream == null:
			push_warning("[AudioBus] Failed to load SFX: %s" % fname)
			continue
		if not _sfx_streams.has(key):
			_sfx_streams[key] = []
		_sfx_streams[key].append(stream)

func _sfx_key_from_filename(stem: String) -> String:
	# Collapse "<key>_NN" variant pools onto the bare key. Filenames that don't
	# end in "_<digits>" (e.g. "combo_success_1_hit") pass through unchanged.
	var rx := RegEx.create_from_string("^(.*)_\\d+$")
	var m := rx.search(stem)
	if m != null:
		return m.get_string(1)
	return stem
