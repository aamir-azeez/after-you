extends "res://tests/test_relay_room_coordinator.gd"
## A duel's room on the phone: its snapshot says `duel: true` (backend
## v2/room.ts), the coordinator keeps it and answers duel_room(), and no turn
## started in it plays with Forgiving catches, whatever the player's setting
## (services/forgiving_catches.gd); the server refuses an assisted turn there.
const ForgivingCatches = preload("res://services/forgiving_catches.gd")
const Registry = preload("res://services/chapter_registry.gd")

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	await _duel_view()
	_rule()
	print("Duel room: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _duel(room: Dictionary, value: Variant = true) -> Dictionary:
	room["duel"] = value
	return room

func _duel_view() -> void:
	# Each boundary is kept for as long as its coordinator asks it who the owner is.
	var boundary := Boundary.new()
	var coordinator = await _open(boundary, _duel(_snapshot(HOST)))
	_check(coordinator.duel_room() and coordinator.snapshot().get("duel") == true, "A duel's room says so and is kept")
	var plain_boundary := Boundary.new()
	var plain = await _open(plain_boundary)
	_check(not plain.duel_room() and not plain.snapshot().has("duel"), "An ordinary room is no duel's room")
	for bad: Variant in [false, "true", 1, null]:
		var bad_boundary := Boundary.new()
		var refused = _coordinator(bad_boundary)
		refused.bind_room(ROOM)
		bad_boundary.responses.append(_ok(_duel(_snapshot(HOST), bad)))
		_check(not await refused.refresh() and not refused.duel_room(), "A duel field that is not exactly true is refused: %s" % [bad])

func _rule() -> void:
	var relay := Registry.RELAY
	_check(ForgivingCatches.on(true, relay, false), "Forgiving catches follow the setting in an ordinary room")
	_check(not ForgivingCatches.on(false, relay, false), "and stay off when the setting is off")
	_check(not ForgivingCatches.on(true, relay, true), "A duel's room never uses them, whatever the setting")
	_check(not ForgivingCatches.on(true, Registry.LIGHTHOUSE_V2, false), "A chapter with no catch to forgive never records them")
	var preview := FileAccess.get_file_as_string("res://relay_preview.gd")
	_check(preview.contains("ForgivingCatches.on(bool(settings.get(\"assistance\", true)), chapter_key, _duel_room())") and preview.contains("online_session.coordinator.duel_room()") and not preview.contains("Registry.catch_assistance(chapter_key)"), "A new turn takes its Forgiving catches from the one rule")
