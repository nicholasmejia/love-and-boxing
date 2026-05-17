extends GutTest

const SaveDataClass := preload("res://scripts/autoload/save_data.gd")

func before_each():
	SaveDataClass.TEST_PATH = "user://test_progress.cfg"
	var f := FileAccess.open(SaveDataClass.TEST_PATH, FileAccess.WRITE)
	if f:
		f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveDataClass.TEST_PATH))

func test_default_unlocked_tier_is_one():
	var sd := SaveDataClass.new()
	sd.use_test_path()
	assert_eq(sd.unlocked_tier(), 1)

func test_unlock_persists():
	var sd := SaveDataClass.new()
	sd.use_test_path()
	sd.unlock_tier(2)
	var sd2 := SaveDataClass.new()
	sd2.use_test_path()
	assert_eq(sd2.unlocked_tier(), 2)

func test_unlock_never_regresses():
	var sd := SaveDataClass.new()
	sd.use_test_path()
	sd.unlock_tier(3)
	sd.unlock_tier(1)
	assert_eq(sd.unlocked_tier(), 3, "Unlocking lower tier must not regress")
