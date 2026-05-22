extends GutTest

func test_title_intro_track_registered():
	assert_true(AudioBus.MUSIC_TRACKS.has("title_intro"),
		"AudioBus.MUSIC_TRACKS should contain 'title_intro' key")
	assert_not_null(AudioBus.MUSIC_TRACKS["title_intro"],
		"'title_intro' should resolve to an AudioStream resource")

func test_title_main_loop_track_registered():
	assert_true(AudioBus.MUSIC_TRACKS.has("title_main_loop"),
		"AudioBus.MUSIC_TRACKS should contain 'title_main_loop' key")
	assert_not_null(AudioBus.MUSIC_TRACKS["title_main_loop"],
		"'title_main_loop' should resolve to an AudioStream resource")
