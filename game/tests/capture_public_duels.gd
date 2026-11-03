extends SceneTree
## Development tool, not a suite: captures the public duel surfaces (boards 1
## to 6 in claude-20261011/public-duels) through the game's own pages, with
## example duels, names and looks and no server. tests/ is never exported.
## Needs a rendered run from a copy of the game whose window is invisible
## (claude-20261010/tools/make-godot-invisible.ps1):
##   godot --path <copy> --resolution 1600x738 --script res://tests/capture_public_duels.gd -- --out=<dir> --suffix=-1600x738
## Writes public-1a-lobby, public-2a-list-alone, public-2b-list-with-maya,
## public-3a-join-beside, public-3b-duel-beside, public-3c-join-pair-spot,
## public-3d-duel-pair-spot, public-4a-join-with-maya, public-4b-duel-with-maya,
## public-5a-post, public-5c-tile, public-6b-first-time, public-6c-stranger,
## public-6d-block and public-result-held; and for a partner who has not accepted
## the community rules, public-2c-list-partner-rules, public-5b-post-partner-rules
## and public-6e-rules-on-lobby (the card their own phone shows on opening Duels).
## Synthetic ids only.
const Client = preload("res://services/duels_client.gd")
const PublicClient = preload("res://services/public_duels_client.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const Lobby = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const ListPage = preload("res://presentation/duels/public_list_page.gd")
const Sheets = preload("res://presentation/duels/public_sheets.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Runs = preload("res://services/leaderboard_runs.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const NOOR := "NNNNNNNNNNNNNNNNNNNNNN"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const NAMES := {ME: "You", MAYA: "Maya", FINN: "Finn", NOOR: "Noor"}
const MAYA_LOOK := {"hat": "daisy"}
const T := 30

class Dressed extends RefCounted:
	func active_look() -> Dictionary: return {"hat": "straw_hat"}

var _out := "."
var _suffix := ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): _out = argument.trim_prefix("--out=")
		if argument.begins_with("--suffix="): _suffix = argument.trim_prefix("--suffix=")
	_run.call_deferred()

func _name_of(id: Variant) -> String:
	return str(NAMES.get(id, ""))

## A list row as the server sends it. `seats`: four [open, label, look]; `steps`: each side's.
func _row(id: String, board: String, minutes: int, seats: Array, steps: Array, mine: bool = false) -> Dictionary:
	var sides: Array = []
	for index in range(2):
		var kept: Array = []
		for slot in range(2):
			var seat: Array = seats[index * 2 + slot]
			kept.append({"open": seat[0], "label": seat[1], "look": seat[2]} if not seat[0] else {"open": true, "label": null})
			if seat.size() > 3: kept[-1]["you"] = true
		sides.append({"steps": steps[index], "seats": kept})
	return PublicClient.valid_row({"duel_id": id.repeat(32 / id.length()), "board": board, "posted_ms": NOW - minutes * 60_000, "open_until_ms": NOW + 86_400_000,
		"steps": Registry.definition(Runs.chapter_of(board) if not Runs.chapter_of(board).is_empty() else board).stages.size() * 2, "mine": mine, "sides": sides})

## A public duel as the server sends it to this player. Each side: [members, seats [open, you, label], steps, ticks, turn, looks].
func _view(id: String, board: String, a: Array, b: Array, status: String = "running", extra: Dictionary = {}) -> Dictionary:
	var steps: int = Registry.definition(Runs.chapter_of(board) if not Runs.chapter_of(board).is_empty() else board).stages.size() * 2
	var side := func(part: Array, own: bool) -> Dictionary:
		var made := {"members": part[0], "you": own, "steps": part[2], "ticks": part[3] * T, "turn": part[4], "finished": false, "left": false, "check": "none", "looks": part[5],
			"seats": part[1].map(func(seat: Array) -> Dictionary: return {"open": seat[0], "you": seat[1], "label": seat[2]})}
		if own: made.merge({"room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true})
		return made
	var open := 0
	for part: Array in [a, b]:
		for seat: Array in part[1]: open += int(seat[0])
	var wire := {"schema_version": 1, "duel_id": id.repeat(32 / id.length()), "kind": "friend", "board": board, "status": status, "steps": steps, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3,
		"mine": 0, "ghost": null, "result": null, "eligible": true, "public": {"posted_ms": NOW, "open_until_ms": NOW + 86_400_000, "seats_open": open}, "sides": [side.call(a, true), side.call(b, false)]}
	wire.merge(extra, true)
	var view := Client.valid_view(wire)
	if view.is_empty(): push_error("capture duel did not read: " + id)
	return view

var NOW := int(Time.get_unix_time_from_system() * 1000.0)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE needs a rendered run; headless draws nothing.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	Catalog.set_offered(["daisy", "seashell", "straw_hat", "tide"])
	Wardrobe.use_shared(Dressed.new())
	var lighthouse := Runs.board_key(Registry.LIGHTHOUSE_V2)
	var high := Runs.board_key(Registry.ROLLING_HOME)
	var relay := Runs.board_key(Registry.RELAY)
	var keys: Array = []
	for key: String in ChapterUnlocks.chain(): if not Runs.board_key(key).is_empty(): keys.append(key)
	var well := Runs.board_key(keys[3]) if keys.size() > 3 else relay
	var tide := Runs.board_key(keys[4]) if keys.size() > 4 else high
	var shell := {"hat": "seashell"}
	var tidey := {"body": "tide"}
	# The lobby with the Public duels row and a posted public duel (boards 1A and 5C).
	var posted := _view("1a", lighthouse, [[ME, MAYA], [[false, true, null], [false, false, null]], 3, 48, 0, [{}, MAYA_LOOK]], [[null, null], [[true, false, null], [true, false, null]], 0, 0, null, [{}, {}]])
	var lobby := Lobby.new()
	lobby.me = ME
	lobby.name_of = _name_of
	lobby.public_shown = true
	root.add_child(lobby)
	lobby.show_lobby(Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null, "partner_look": MAYA_LOOK},
		"duels": [_wire_of(posted)], "public": {"version": 1, "on": true, "show_name": true, "partner_on": true, "paused": false, "running": 1}}))
	await _save("public-1a-lobby")
	# The rules card a player who has not accepted the rules meets on opening Duels (public_duels_flow.gd ask_rules).
	lobby.hold_modal(Sheets.first_time(lobby.root, false, func(_named: bool) -> void: pass, PlayerCopy.PUBLIC_FIRST_CONTINUE))
	await _save("public-6e-rules-on-lobby")
	lobby._modal.close()
	# The list, Alone, then With Maya (boards 2A, 2B).
	var rows := [
		_row("2a", lighthouse, 4, [[false, "Kite", shell], [true], [true], [true]], [1, 0]),
		_row("2b", high, 20, [[false, null, tidey], [false, null, {}], [false, "Juniper", shell], [true]], [2, 2]),
		_row("2c", tide, 60, [[false, null, {}], [true], [false, "Moss", tidey], [true]], [2, 2]),
		_row("2d", well, 120, [[false, null, {}, true], [false, "Maya", MAYA_LOOK], [true], [true]], [3, 0], true),
		_row("2e", relay, 180, [[false, "Pebble", shell], [false, null, {}], [true], [true]], [3, 0])]
	var list := ListPage.new()
	list.partner_name = "Maya"
	list.partner_look = MAYA_LOOK
	list.boards = keys.map(func(key: String) -> Array: return [Runs.board_key(key), key])
	list.known = func(_row_now: Dictionary) -> Dictionary: return {"chapter_open": true, "partner_on": true, "at_limit": false}
	lobby.open_overlay(list)
	list.show_rows(rows, -1)
	await _save("public-2a-list-alone")
	list._set_joining("party")
	await _save("public-2b-list-with-maya")
	# Maya has not accepted the community rules: every party Join greys with the reason.
	var known_before: Callable = list.known
	list.known = func(_row_now: Dictionary) -> Dictionary: return {"chapter_open": true, "partner_on": true, "partner_rules": false, "at_limit": false}
	list.redraw()
	await _save("public-2c-list-partner-rules")
	list.known = known_before
	list.redraw()
	# Joining beside Kite (board 3, top).
	list._set_joining("alone")
	var names := {"title": "Sleeping Lighthouse", "partner": "Maya", "partner_look": MAYA_LOOK}
	list.hold_modal(Sheets.join(list.root, rows[0], 1, "alone", names, func() -> void: pass))
	await _save("public-3a-join-beside")
	list._modal.close()
	list.hold_modal(Sheets.join(list.root, rows[0], 2, "alone", names, func() -> void: pass))
	await _save("public-3c-join-pair-spot")
	list._modal.close()
	list.hold_modal(Sheets.join(list.root, rows[0], 2, "party", names, func() -> void: pass))
	await _save("public-4a-join-with-maya")
	list.close()
	# The duel pages each join opens (boards 3 and 4, right).
	var beside := _view("3b", lighthouse, [[ME, null], [[false, true, null], [false, false, "Kite"]], 1, 21, 0, [{}, shell]], [[null, null], [[true, false, null], [true, false, null]], 0, 0, null, [{}, {}]])
	await _duel_shot(lobby, beside, "public-3b-duel-beside", {"amount": 30, "state": "running", "reason": ""})
	var pair_spot := _view("3d", lighthouse, [[ME, null], [[false, true, null], [true, false, null]], 0, 0, -1, [{}, {}]], [[null, null], [[false, false, "Kite"], [true, false, null]], 1, 21, 1, [shell, {}]])
	await _duel_shot(lobby, pair_spot, "public-3d-duel-pair-spot")
	var with_maya := _view("4b", lighthouse, [[ME, MAYA], [[false, true, null], [false, false, null]], 0, 0, -1, [{}, MAYA_LOOK]], [[null, null], [[false, false, "Kite"], [true, false, null]], 1, 21, 1, [shell, {}]])
	await _duel_shot(lobby, with_maya, "public-4b-duel-with-maya")
	# Start a duel's Anyone (board 5A).
	var start := ChallengePage.new()
	start.friends = [{"id": FINN, "name": "Finn"}, {"id": NOOR, "name": "Noor"}]
	start.chapters = keys
	start.public_offered = true
	start.anyone = true
	start.partner_name = "Maya"
	start.partner_look = MAYA_LOOK
	lobby.open_overlay(start)
	await process_frame
	start._pick_chapter(Registry.LIGHTHOUSE_V2)
	await _save("public-5a-post")
	start.set_party_reason(PlayerCopy.PUBLIC_PARTNER_RULES % "Maya")
	await _save("public-5b-post-partner-rules")
	start.close()
	# The lobby tile of a posted duel (board 5C) is in public-1a-lobby; the safety cards (board 6).
	var strangers := _view("6a", lighthouse, [[ME, null], [[false, true, null], [false, false, "Kite"]], 1, 21, 1, [{}, shell]], [[null, null], [[false, false, null], [false, false, null]], 2, 34, 0, [tidey, {}]])
	var page := DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = strangers
	lobby.open_overlay(page)
	page.hold_modal(Sheets.first_time(page.root, false, func(_named: bool) -> void: pass))
	await _save("public-6b-first-time")
	page._modal.close()
	page.hold_modal(Sheets.stranger(page.root, {"name": "Kite", "partner": true, "color": "mint", "look": shell, "over": false, "duel_id": strangers.duel_id}, {}, {"report": func() -> void: pass, "block": func() -> void: pass}))
	await _save("public-6c-stranger")
	page._modal.close()
	page.hold_modal(Sheets.block(page.root, "Kite", true, func() -> void: pass))
	await _save("public-6d-block")
	page.close()
	# A result whose held duel extra was not paid.
	var result := ResultPage.new()
	result.me = ME
	result.name_of = _name_of
	var ended := strangers.duplicate(true)
	ended.status = "unfinished"
	ended.result = {"outcome": "none", "reason": "nobody_joined", "margin_ticks": -1}
	result.view = ended
	result.pay = {"turns": 1, "plain": 60, "blooms": 0, "duel": 0, "duel_percent": 50, "boost": 0, "boost_percent": 0, "total": 60, "held": 30}
	result.held = {"amount": 30, "state": "forfeit", "reason": "nobody_joined"}
	lobby.open_overlay(result)
	await _save("public-result-held")
	result.close()
	quit(0)

func _duel_shot(lobby: CanvasLayer, view: Dictionary, name: String, held: Dictionary = {}) -> void:
	var page := DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = view
	lobby.open_overlay(page)
	page.held = held
	await _save(name)
	page.close()

## A kept view back as the server would send it (the lobby reads wires).
func _wire_of(view: Dictionary) -> Dictionary:
	var sides: Array = []
	for side: Dictionary in view.sides:
		var wire := side.duplicate(true)
		wire.turn = side.turn if side.turn >= 0 else null
		sides.append(wire)
	return {"schema_version": 1, "duel_id": view.duel_id, "kind": view.kind, "board": view.board, "status": view.status, "steps": view.steps, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3,
		"mine": view.mine, "ghost": null, "result": null, "eligible": true, "public": view.public, "sides": sides}

func _save(name: String, frames: int = 30) -> void:
	var waited := 0
	while (Snapshots.pending() > 0 or waited < frames) and waited < 600:
		await process_frame
		waited += 1
	await RenderingServer.frame_post_draw
	var path := "%s/%s%s.png" % [_out, name, _suffix]
	print("SAVED %s %s" % [path, error_string(root.get_texture().get_image().save_png(path))])
