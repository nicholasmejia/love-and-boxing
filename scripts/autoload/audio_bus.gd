extends Node

# First-pass implementation: log the SFX call but don't play anything.
# Real audio is wired in a later milestone.

func play_sfx(name: String) -> void:
	print("[AudioBus] play_sfx: %s" % name)

func play_music(name: String) -> void:
	print("[AudioBus] play_music: %s" % name)

func stop_music() -> void:
	print("[AudioBus] stop_music")
