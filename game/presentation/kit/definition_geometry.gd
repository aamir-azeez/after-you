extends RefCounted
## World kit: geometry a world works out from its chapter definition alone
## (wall layouts, water surfaces), kept once per key for the session and
## shared by every world that asks, so a second open of a chapter, or of its
## other stage, builds none of it again. A kept value is never changed in
## place: a mesh kept here is drawn by every world that asks for it.
##
## Keys are Arrays of the exact inputs (an Array hashes and compares by value),
## led by a name for what is kept. The kit lives in a script that extends an
## engine class: a static var in a subclass of a project script can crash the
## exit (tests/test_subclass_statics.gd).
const SessionRelease = preload("res://presentation/kit/session_release.gd")
static var _kept: Dictionary = {}

## Whether a value is kept for key.
static func has(key: Array) -> bool:
	return _kept.has(key)

## The value kept for key, or null.
static func kept(key: Array) -> Variant:
	return _kept.get(key)

## Keeps value for key unless one is kept already, and returns the kept one, so
## two builds that worked it out at once both end up with the same value.
static func keep(key: Array, value: Variant) -> Variant:
	if not _kept.has(key):
		_kept[key] = value
		# Kept meshes go before the renderer stops, not when this script is freed.
		SessionRelease.on_exit(Callable(load("res://presentation/kit/definition_geometry.gd"), "release"))
	return _kept[key]

## Lets go of everything kept (SessionRelease calls this at shutdown).
static func release() -> void:
	_kept.clear()
