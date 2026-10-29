extends RefCounted
## Whether a new turn plays with Forgiving catches: the player's setting
## ("assistance"), in a chapter family that has a catch to forgive
## (ChapterRegistry.catch_assistance), and never in a duel's room, whose
## server refuses an assisted turn (backend v2/room.ts "duel_turn_assisted")
## because a duel races unassisted runs. One rule, read at the start of every
## turn (relay_preview.gd).
const Registry = preload("res://services/chapter_registry.gd")

static func on(setting: bool, chapter_key: String, duel_room: bool) -> bool:
	return setting and not duel_room and Registry.catch_assistance(chapter_key)
