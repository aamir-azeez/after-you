extends SceneTree

const Main = preload("res://main.gd")
const Reactions = preload("res://presentation/room_reactions.gd")
const Storage = preload("res://services/local_save.gd")
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"

class Harness:
	extends Main
	var notices: Array[String] = []
	var accepted := 0
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func _physics_process(_delta: float) -> void:
		pass
	func _notification(_what: int) -> void:
		pass
	func _toast(message: String) -> void:
		notices.append(message)
	func _accept_room(response: Dictionary) -> void:
		accepted += 1
		active_room = response.data.duplicate(true)

class FakeApi:
	extends Node
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var busy := false
	var calls: Array[Dictionary] = []
	var responses: Array[Dictionary] = []
	var during: Callable
	func request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
		calls.append({"method": method, "path": path, "body": body.duplicate(true)})
		busy = true
		if during.is_valid():
			var action := during
			during = Callable()
			action.call()
		await get_tree().process_frame
		busy = false
		return responses.pop_front() if not responses.is_empty() else {"ok": false, "error": "Synthetic unavailable"}

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _room(reactions: Dictionary = {}, revision: int = 5) -> Dictionary:
	return {"room_id": "R".repeat(22), "attempt": 0, "level_id": "first-light", "level_index": 0,
		"host_id": HOST, "guest_id": GUEST, "active_role": "complete", "revision": revision, "reactions": reactions.duplicate(true)}

func _reset(app: Harness, api: FakeApi) -> void:
	app.active_room = _room()
	app.mode = "room"
	app.room_play = true
	app.identity_loading = false
	app.identity_busy = false
	app.identity_restart_required = false
	app.identity_read_state = Main.IdentityReadState.LOADED
	app.pending_recovery = {}
	app.relay_identity_epoch = 0
	app.lifecycle_generation = 0
	app.notices.clear()
	app.accepted = 0
	app.saves.data.erase("pending_turn")
	api.busy = false
	api.player_id = HOST
	api.calls.clear()
	api.responses.clear()
	api.during = Callable()

func _run() -> void:
	_check(Reactions.code_for_label("Beautiful!") == "love", "Existing Beautiful preset keeps its wire code")
	_check(Reactions.code_for_label("We did it!") == "sparkles", "Existing shared-success preset keeps its wire code")
	_check(Reactions.code_for_label("Again soon") == "again", "Existing Again preset keeps its wire code")
	_check(Reactions.code_for_label("arbitrary text").is_empty(), "Unsupported input cannot become a message")
	var both := _room({HOST: "love", GUEST: "again", "outsider": "sparkles"})
	var rows: Array[Dictionary] = Reactions.rows(both, HOST)
	_check(rows.size() == 2 and rows[0].text == "Your friend reacted: Again soon" and not rows[0].own, "Friend response appears before own confirmation")
	_check(rows[1].text == "Your reaction: Beautiful!" and rows[1].own, "Own preset remains visible without pretending it came from a friend")
	_check(not JSON.stringify(rows).contains(HOST) and not JSON.stringify(rows).contains(GUEST), "Display rows contain no player identifiers")
	_check(Reactions.rows(both, "outsider").is_empty(), "Nonmember view cannot produce reaction rows")
	_check(Reactions.rows(_room({GUEST: "arbitrary text"}), HOST).is_empty(), "Unknown received text is ignored")
	var unfinished := both.duplicate(true)
	unfinished.active_role = "a"
	_check(Reactions.rows(unfinished, HOST).is_empty(), "Old completion reactions are not shown as current during a new turn")
	var seen: Dictionary = {}
	var before := _room()
	var after := _room({GUEST: "love"}, 6)
	_check(Reactions.new_partner_notice({}, after, HOST, seen).is_empty(), "Initial load renders history without a new-reaction toast")
	_check(Reactions.new_partner_notice(before, _room({HOST: "love"}), HOST, seen).is_empty(), "Own reaction never generates a friend toast")
	_check(Reactions.new_partner_notice(before, after, HOST, seen) == "Your friend reacted: Beautiful!", "Fresh friend response creates one modest notice")
	_check(Reactions.new_partner_notice(before, after, HOST, seen).is_empty(), "Repeated stale-to-current response is deduplicated")
	_check(Reactions.new_partner_notice(after, after, HOST, seen).is_empty(), "Unchanged polling response stays quiet")
	var next_attempt := after.duplicate(true)
	next_attempt.attempt = 1
	_check(Reactions.new_partner_notice(before, next_attempt, HOST, seen).is_empty(), "A changed attempt does not mislabel an older reaction as new")
	for index in range(132):
		var old := _room()
		var fresh := _room({GUEST: "love"})
		old.room_id = "synthetic-room-" + str(index)
		fresh.room_id = old.room_id
		Reactions.new_partner_notice(old, fresh, HOST, seen)
	_check(seen.size() == Reactions.MAX_NOTICES, "Long foreground use keeps dedup memory bounded")

	var app := Harness.new()
	app.saves = Storage.new("user://unused-reaction-test.json")
	root.add_child(app)
	var api := FakeApi.new()
	app.add_child(api)
	app.api = api
	_reset(app, api)
	var card := VBoxContainer.new()
	app.add_child(card)
	app._add_room_reaction_summary(card, both)
	_check(card.get_child_count() == 2, "Actual main summary helper renders both current presets")
	_check(card.get_child(0).name == "FriendRoomReaction" and card.get_child(0).text == "Your friend reacted: Again soon", "Friend card receives its readable reaction label")
	app._notice_room_reactions(before, after)
	app._notice_room_reactions(before, after)
	_check(app.notices.size() == 1 and app.notices[0] == "Your friend reacted: Beautiful!", "Actual main notice helper deduplicates fresh updates")

	_reset(app, api)
	api.responses.append({"ok": true, "data": _room({HOST: "love"}, 6)})
	await app._react("Beautiful!")
	_check(api.calls.size() == 1 and api.calls[0].body.reaction == "love", "Send uses the supported preset code")
	_check(app.accepted == 1 and app.notices.back() == "Reaction sent.", "Only a matching server acknowledgement confirms sending")
	_reset(app, api)
	await app._react("not a preset")
	_check(api.calls.is_empty(), "Unknown preset sends no request")
	api.busy = true
	await app._react("Beautiful!")
	_check(api.calls.is_empty(), "A competing request cannot start a second transport call")
	_reset(app, api)
	app.saves.data.pending_turn = {"held": true}
	await app._react("Beautiful!")
	_check(api.calls.is_empty(), "An uncertain gameplay submission remains ahead of optional reactions")
	_reset(app, api)
	api.responses.append({"ok": true, "data": _room({GUEST: "love"}, 6)})
	await app._react("Beautiful!")
	_check(app.accepted == 0 and not app.notices.has("Reaction sent."), "Another participant's value cannot falsely acknowledge my reaction")
	_reset(app, api)
	api.responses.append({"ok": false, "error": "Synthetic interrupted response"})
	await app._react("Beautiful!")
	_check(app.accepted == 0 and not app.notices.has("Reaction sent."), "Lost acknowledgement is not reported as delivery")

	for invalidation: String in ["identity", "room", "screen", "lifecycle"]:
		_reset(app, api)
		api.responses.append({"ok": true, "data": _room({HOST: "love"}, 6)})
		api.during = func():
			match invalidation:
				"identity": app.relay_identity_epoch += 1
				"room": app.active_room.room_id = "another-room"
				"screen": app.mode = "settings"
				"lifecycle": app.lifecycle_generation += 1
		await app._react("Beautiful!")
		_check(app.accepted == 0 and app.notices.is_empty(), "Late reply after " + invalidation + " change cannot revive the prior room")

	_reset(app, api)
	api.responses.append({"ok": false, "code": "stale_revision", "error": "Synthetic conflict"})
	api.responses.append({"ok": true, "data": _room({GUEST: "again"}, 6)})
	api.responses.append({"ok": true, "data": _room({GUEST: "again", HOST: "love"}, 7)})
	await app._react("Beautiful!")
	_check(api.calls.size() == 3 and api.calls[1].method == HTTPClient.METHOD_GET, "Simultaneous reactions refresh once before retrying")
	_check(api.calls[2].body.base_revision == 6 and api.calls[2].body.idempotency_key != api.calls[0].body.idempotency_key, "Retry uses the refreshed revision and a distinct request body identity")
	_check(app.accepted == 1 and app.active_room.reactions[GUEST] == "again", "Conflict recovery keeps the friend's already accepted reaction")
	_reset(app, api)
	api.responses.append({"ok": false, "code": "stale_revision", "error": "Synthetic conflict"})
	api.responses.append({"ok": true, "data": next_attempt})
	await app._react("Beautiful!")
	_check(api.calls.size() == 2 and app.accepted == 0, "Conflict retry never moves a reaction onto a different attempt")
	_reset(app, api)
	api.responses.append({"ok": false, "code": "stale_revision", "error": "Synthetic conflict"})
	api.responses.append({"ok": true, "data": _room({}, 6)})
	api.responses.append({"ok": false, "code": "stale_revision", "error": "Synthetic second conflict"})
	await app._react("Beautiful!")
	_check(api.calls.size() == 3 and app.accepted == 0, "A second conflict stops rather than producing a retry storm")

	app.queue_free()
	await process_frame
	await process_frame
	print("AFTER YOU ROOM REACTIONS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
