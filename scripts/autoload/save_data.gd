extends Node

const DEFAULT_PATH := "user://progress.cfg"
static var TEST_PATH := ""

var _path: String = DEFAULT_PATH
var _config := ConfigFile.new()

func _ready() -> void:
	_load()

func use_test_path() -> void:
	_path = TEST_PATH
	_config = ConfigFile.new()
	_load()

func unlocked_tier() -> int:
	return _config.get_value("progress", "unlocked_tier", 1)

func unlock_tier(tier: int) -> void:
	var current := unlocked_tier()
	if tier <= current:
		return
	_config.set_value("progress", "unlocked_tier", tier)
	_config.save(_path)

func best_time_seconds(tier: int) -> float:
	return _config.get_value("progress", "best_time_tier_%d" % tier, 0.0)

func set_best_time_seconds(tier: int, seconds: float) -> void:
	if seconds <= 0.0:
		return
	var current := best_time_seconds(tier)
	if current > 0.0 and seconds >= current:
		return
	_config.set_value("progress", "best_time_tier_%d" % tier, seconds)
	_config.save(_path)

# Audio preferences. Stored in a separate section so reset() leaves them alone —
# wiping progress shouldn't silence the player's tuned volumes.
func bgm_volume_percent() -> int:
	return _config.get_value("audio", "bgm_volume_percent", 100)

func sfx_volume_percent() -> int:
	return _config.get_value("audio", "sfx_volume_percent", 100)

func set_bgm_volume_percent(percent: int) -> void:
	_config.set_value("audio", "bgm_volume_percent", percent)
	_config.save(_path)

func set_sfx_volume_percent(percent: int) -> void:
	_config.set_value("audio", "sfx_volume_percent", percent)
	_config.save(_path)

func reset() -> void:
	_config.erase_section("progress")
	_config.save(_path)

func _load() -> void:
	var err := _config.load(_path)
	if err != OK:
		_config.set_value("progress", "unlocked_tier", 1)
