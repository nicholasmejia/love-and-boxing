extends GutTest

const SaveDataClass := preload("res://scripts/autoload/save_data.gd")
const TEST_PATH := "user://test_progress.cfg"

func before_each():
	SaveDataClass.TEST_PATH = TEST_PATH
	_remove_test_file()

func after_each():
	_remove_test_file()

func test_default_unlocked_tier_is_one():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	assert_eq(sd.unlocked_tier(), 1)

func test_unlock_persists():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.unlock_tier(2)
	var sd2: Node = autofree(SaveDataClass.new())
	sd2.use_test_path()
	assert_eq(sd2.unlocked_tier(), 2)

func test_unlock_never_regresses():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.unlock_tier(3)
	sd.unlock_tier(1)
	assert_eq(sd.unlocked_tier(), 3, "Unlocking lower tier must not regress")

func test_default_best_time_is_zero():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	assert_eq(sd.best_time_seconds(1), 0.0)

func test_best_time_persists():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.set_best_time_seconds(2, 123.45)
	var sd2: Node = autofree(SaveDataClass.new())
	sd2.use_test_path()
	assert_almost_eq(sd2.best_time_seconds(2), 123.45, 0.001)

func test_best_time_never_regresses():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.set_best_time_seconds(1, 100.0)
	sd.set_best_time_seconds(1, 200.0)
	assert_almost_eq(sd.best_time_seconds(1), 100.0, 0.001, "Slower time must not overwrite a faster PR")

func test_best_time_improves_on_faster():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.set_best_time_seconds(1, 100.0)
	sd.set_best_time_seconds(1, 75.5)
	assert_almost_eq(sd.best_time_seconds(1), 75.5, 0.001)

func test_reset_clears_best_times():
	var sd: Node = autofree(SaveDataClass.new())
	sd.use_test_path()
	sd.set_best_time_seconds(1, 50.0)
	sd.reset()
	assert_eq(sd.best_time_seconds(1), 0.0)

func _remove_test_file() -> void:
	var absolute := ProjectSettings.globalize_path(TEST_PATH)
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(absolute)
