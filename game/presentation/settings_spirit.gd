extends "res://presentation/kit/pip_avatar.gd"
## The player's own pip in the Settings header (presentation/kit/pip_avatar.gd,
## live): in a three-quarter view facing a little toward the title beside it,
## pulled back a little when a tall item is worn. The page ticks a light
## haptic on `turn.grabbed`.

func _init(reduced: bool = false) -> void:
	super(reduced, PEACH, MIN_SIZE, false, true)
	name = "SettingsSpirit"
