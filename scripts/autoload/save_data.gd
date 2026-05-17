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

func _load() -> void:
	var err := _config.load(_path)
	if err != OK:
		_config.set_value("progress", "unlocked_tier", 1)
