extends SceneTree
## The race ghost (race-picker boards 4A and 5C): the raced run's track for
## every chapter's stages and roles, the same on every build of it; the replay
## kept from the race's first turn to its end and let go after; the ghost's
## look and name; the see-through pip, its faint name and the timer mark.
## Real whole runs come from content/dev_ghosts.json (the developers'
## ghosts, each a final checkpoint in the shared blob format). Synthetic ids only.
const Track = preload("res://services/race_ghost_track.gd")
const RaceGhost = preload("res://services/race_ghost.gd")
const TheirRun = preload("res://services/duel_their_run.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const View = preload("res://presentation/race_ghost_view.gd")
const TimerBar = preload("res://presentation/seed_timer_bar.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Outfit = preload("res://services/outfit.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const OWNER := "GGGGGGGGGGGGGGGGGGGGGG"
const PARTNER := "HHHHHHHHHHHHHHHHHHHHHH"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const DUEL := "d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1"
const ENTRY := "e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2"

var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(message)

class FakeApi extends Node:
	var player_id := OWNER
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, _body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var name: String = {HTTPClient.METHOD_GET: "GET", HTTPClient.METHOD_POST: "POST"}.get(method, "?")
		requests.append(name + " " + path)
		await Engine.get_main_loop().process_frame
		return replies.get(name + " " + path, {"ok": false, "status": 404, "code": "not_found"}).duplicate(true)

## A chapter world as the ghost needs it: pips by slot under one parent.
class FakeWorld extends Node3D:
	var actors: Dictionary = {}

func _run() -> void:
	_clear()
	var ghosts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/dev_ghosts.json")).ghosts
	_check(ghosts.size() >= 12, "the developers' whole runs load: %d" % ghosts.size())
	for row: Dictionary in ghosts: _tracks(row)
	var relay: Dictionary = ghosts.filter(func(row: Dictionary) -> bool: return row.board == "relay-isles@2")[0]
	await _service(relay)
	await _view()
	_clear()
	print("AFTER YOU RACE GHOST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every stage and role of a whole run has a track that walks its turn: as long
## as the turn, the same on a second build, starting where the turn starts.
func _tracks(row: Dictionary) -> void:
	var parts := TheirRun.parts({"digest": row.proof_hash, "byte_length": int(row.byte_length), "body": row.body}, str(row.board))
	_check(not parts.is_empty(), "%s decodes to its stages" % row.board)
	if parts.is_empty(): return
	var total := 0
	var moved := false
	for part: Dictionary in parts:
		for role: String in ["a", "b"]:
			var track := Track.build(str(row.board), part.pair, role)
			var where := "%s stage %d turn %s" % [row.board, int(part.pair.stage_index), role]
			_check(not track.is_empty() and str(track.slot) == str(part.pair[role].player_slot), "%s has a track for its own player" % where)
			if track.is_empty(): continue
			_check(int(track.duration_ticks) == int(part.pair[role].duration_ticks), "%s is as long as the turn: %d of %d ticks" % [where, int(track.duration_ticks), int(part.pair[role].duration_ticks)])
			total += int(track.duration_ticks)
			if Track.point(track, 0) != Track.point(track, int(track.duration_ticks)): moved = true
			_check(Track.point(track, -5) == Track.point(track, 0) and Track.point(track, 1 << 20) == Track.point(track, int(track.duration_ticks)), "%s holds its first and last points past either end" % where)
	_check(moved, "%s's ghost walks" % row.board)
	_check(total == int(row.ticks), "%s's tracks add up to the run's time: %d of %d" % [row.board, total, int(row.ticks)])
	var first: Dictionary = parts[0].pair
	_check(Track.build(str(row.board), first, "b").points == Track.build(str(row.board), first, "b").points, "%s builds the same track every time" % row.board)
	_check(Track.build(str(row.board), first, "c").is_empty() and Track.build(str(row.board), {"a": first.a}, "a").is_empty(), "%s: a role or set-up the run lacks has no track" % row.board)
	# A turn this build plays differently from its recording (a replay check off) shows no ghost, never a wrong one.
	for role: String in ["a", "b"]:
		var off: Dictionary = first.duplicate(true)
		off[role].replay_checks[-1].state_hash = "0".repeat(64)
		_check(Track.build(str(row.board), off, role).is_empty(), "%s turn %s: a replay check that does not match gives no track" % [row.board, role])

## The service: the race found by its room, the replay fetched once and kept,
## the look and name, a turn after the board stopped serving the run, and the copy let go when the race ends.
func _service(relay: Dictionary) -> void:
	var api := FakeApi.new()
	root.add_child(api)
	var board := str(relay.board)
	var chapter := str(relay.board)
	var race := _race_view(board, "running", str(relay.proof_hash))
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": PARTNER, "intact": true, "invites_in": [], "invite_out": null}, "duels": [race]}}
	var replay_path := "GET /v1/leaderboards/%s/replay/%s" % [board, ENTRY]
	api.replies[replay_path] = {"ok": true, "data": {"schema_version": 1, "board": board, "entry_id": ENTRY, "rank": 1, "ticks": int(relay.ticks), "finished_on": "2026-11-01", "names": ["Lee", "Sam"], "gold_leaf": true, "digest": relay.proof_hash, "byte_length": int(relay.byte_length), "body": relay.body}}
	api.replies["GET /v1/leaderboards/" + board] = {"ok": true, "data": {"schema_version": 1, "board": board, "top": [{"rank": 1, "entry_id": ENTRY, "ticks": int(relay.ticks), "names": ["Lee", "Sam"], "gold_leaf": true, "replay_hash": relay.proof_hash}], "checking": []}}
	var service: RefCounted = RaceGhost.new(api, OWNER)
	_check(DuelsClient.valid_view(race).ghost.replay_hash == relay.proof_hash and DuelsClient.valid_view(race).ghost.entry_id == ENTRY, "a race keeps the raced run's entry and replay_hash")
	var turn: Dictionary = await service.turn(ROOM, true, chapter, 0, "a")
	_check(not turn.is_empty() and api.requests.count("GET /v1/duels") == 1, "a duel room with no race read yet reads the lobby once and finds its race")
	var index := 1 if str(turn.get("slot")) == "p1" else 0
	_check(turn.get("look") == Outfit.from(race.ghost.looks[index]) and turn.get("name") == ["Lee", "Sam"][index], "the ghost wears the raced player's look and name, by their slot: %s %s %s" % [turn.get("slot"), turn.get("look"), turn.get("name")])
	_check(TheirRun.kept_run(OWNER, DUEL, true).get("digest") == relay.proof_hash and TheirRun.kept_run(OWNER, DUEL).is_empty(), "the replay is kept on the phone, still encoded, as a ghost copy apart from a duel's other run")
	var second: Dictionary = await service.turn(ROOM, true, chapter, 0, "b")
	_check(not second.is_empty() and api.requests.count(replay_path) == 1 and api.requests.count("GET /v1/duels") == 1, "the next turn reads nothing more")
	# The board stops serving the run (an erased account, or it left the top 10): the race keeps playing from the copy.
	api.replies.erase(replay_path)
	api.replies["GET /v1/leaderboards/" + board] = {"ok": true, "data": {"schema_version": 1, "board": board, "top": [], "checking": []}}
	var later: RefCounted = RaceGhost.new(api, OWNER)
	DuelsClient.shared(api, OWNER)
	var kept_turn: Dictionary = await later.turn(ROOM, true, chapter, 1, "a")
	_check(RaceGhost.KEEP_COPY_UNTIL_RACE_ENDS and not kept_turn.is_empty() and api.requests.count(replay_path) == 1, "after the board stops serving it, the race still plays the kept copy (owner, 2026-11-03)")
	# A friend room, or a room never raced: no ghost.
	_check((await later.turn("SSSSSSSSSSSSSSSSSSSSSS", false, chapter, 0, "a")).is_empty(), "a room that is no ghost race has no ghost")
	# The race ends: its copy goes.
	later.release_ended({"duels": [DuelsClient.valid_view(_race_view(board, "running", str(relay.proof_hash)))]})
	_check(not TheirRun.kept_run(OWNER, DUEL, true).is_empty(), "a running race keeps its copy")
	later.release_ended({"duels": [DuelsClient.valid_view(_race_view(board, "decided", str(relay.proof_hash)))]})
	_check(TheirRun.kept_run(OWNER, DUEL, true).is_empty(), "the copy goes once the race has ended")
	await _copies(relay)
	# Our run plays from the run the game ships, with no request, in the default look.
	var ours := _race_view(board, "running", str(relay.proof_hash))
	ours.ghost = {"source": "developer", "entry_id": null, "rank": null, "ticks": int(relay.ticks), "names": null}
	api.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": PARTNER, "intact": true, "invites_in": [], "invite_out": null}, "duels": [ours]}}
	await DuelsClient.shared(api, OWNER).lobby()
	var asked := api.requests.size()
	var developer: Dictionary = await RaceGhost.new(api, OWNER).turn(ROOM, true, chapter, 0, "a")
	_check(not developer.is_empty() and developer.developer and developer.look == {} and api.requests.size() == asked, "a race against Our run plays the shipped run, asking nothing")
	_check(RaceGhost.developer_run(board, int(relay.ticks) + 1).is_empty() and RaceGhost.developer_run("no-such-board@1", 1).is_empty(), "a race whose time is not the shipped run's has no ghost")
	api.queue_free()
	await _drop_mode(relay)

## The other side of the erasure switch (KEEP_COPY_UNTIL_RACE_ENDS false): the
## run plays while the board lists it, nothing is kept, and once the board
## stops serving it the next turn has no ghost.
func _drop_mode(relay: Dictionary) -> void:
	var board := str(relay.board)
	var race := _race_view(board, "running", str(relay.proof_hash))
	race.duel_id = "b".repeat(32)
	var row := {"rank": 1, "entry_id": ENTRY, "ticks": int(relay.ticks), "names": null, "gold_leaf": true, "replay_hash": relay.proof_hash}
	var served := FakeApi.new()
	root.add_child(served)
	served.replies["GET /v1/duels"] = {"ok": true, "data": {"schema_version": 1, "party": {"partner": PARTNER, "intact": true, "invites_in": [], "invite_out": null}, "duels": [race]}}
	served.replies["GET /v1/leaderboards/%s/replay/%s" % [board, ENTRY]] = {"ok": true, "data": {"schema_version": 1, "board": board, "entry_id": ENTRY, "rank": 1, "ticks": int(relay.ticks), "finished_on": "2026-11-01", "names": null, "gold_leaf": true, "digest": relay.proof_hash, "byte_length": int(relay.byte_length), "body": relay.body}}
	served.replies["GET /v1/leaderboards/" + board] = {"ok": true, "data": {"schema_version": 1, "board": board, "top": [row], "checking": []}}
	var service: RefCounted = RaceGhost.new(served, OWNER)
	service.keep_copy = false
	_check(not (await service.turn(ROOM, true, board, 0, "a")).is_empty() and TheirRun.kept_ghosts(OWNER).is_empty(), "switched to drop: the run plays while the board lists it, and nothing is kept")
	# The board stops serving it (a fresh read: a phone keeps a board a minute).
	var gone := FakeApi.new()
	root.add_child(gone)
	gone.replies["GET /v1/duels"] = served.replies["GET /v1/duels"]
	gone.replies["GET /v1/leaderboards/" + board] = {"ok": true, "data": {"schema_version": 1, "board": board, "top": [], "checking": []}}
	service._api = gone
	_check((await service.turn(ROOM, true, board, 1, "a")).is_empty() and TheirRun.kept_ghosts(OWNER).is_empty(), "and the next turn after the board stops serving it has no ghost")
	served.queue_free()
	gone.queue_free()

## Ghost copies never push out another pair's run, stay few, go when the
## lobby no longer shows their race, and are never written for an erased player.
func _copies(relay: Dictionary) -> void:
	var blob := {"digest": relay.proof_hash, "byte_length": int(relay.byte_length), "body": relay.body}
	var friend_run := "f".repeat(32)
	TheirRun.keep(OWNER, friend_run, blob)
	for index in range(TheirRun.MAX_GHOST_KEPT + 3):
		TheirRun.keep(OWNER, ("%02d" % index).repeat(16), blob, true)
	_check(TheirRun.kept_ghosts(OWNER).size() == TheirRun.MAX_GHOST_KEPT and not TheirRun.kept_run(OWNER, friend_run).is_empty(), "ghost copies stay at most %d, and the other pair's run stays" % TheirRun.MAX_GHOST_KEPT)
	RaceGhost.new(null, OWNER).release_ended({"duels": []})
	_check(TheirRun.kept_ghosts(OWNER).is_empty() and not TheirRun.kept_run(OWNER, friend_run).is_empty(), "a lobby that no longer shows a race lets its copy go, and only ghost copies")
	TheirRun.forget(OWNER, friend_run)
	# Erased while a read is out: nothing is written back.
	var api := FakeApi.new()
	root.add_child(api)
	var replay_path := "GET /v1/leaderboards/%s/replay/%s" % [relay.board, ENTRY]
	api.replies[replay_path] = {"ok": true, "data": {"schema_version": 1, "board": relay.board, "entry_id": ENTRY, "rank": 1, "ticks": int(relay.ticks), "finished_on": "2026-11-01", "names": null, "gold_leaf": true, "digest": relay.proof_hash, "byte_length": int(relay.byte_length), "body": relay.body}}
	var erased: RefCounted = RaceGhost.shared(api, OWNER)
	var race := DuelsClient.valid_view(_race_view(str(relay.board), "running", str(relay.proof_hash)))
	race.duel_id = "c".repeat(32)
	erased.prefetch(race)
	RaceGhost.clear_owner(OWNER)
	for frame in range(4): await process_frame
	_check(TheirRun.kept_run(OWNER, race.duel_id, true).is_empty() and RaceGhost.shared(api, OWNER) != erased, "a read still out when the account is erased writes nothing back")
	api.queue_free()

## A ghost race against the board's run, played in ROOM.
func _race_view(board: String, status: String, replay_hash: String) -> Dictionary:
	var side := {"members": [OWNER, PARTNER], "you": true, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": null, "hosting": true}
	return {"schema_version": 1, "duel_id": DUEL, "kind": "ghost", "board": board, "status": status, "steps": 4, "created_ms": 1, "accepted_ms": 1, "updated_ms": 2 if status == "decided" else 1, "mine": 0,
		"ghost": {"source": "board", "entry_id": ENTRY, "rank": 1, "ticks": 588, "names": null, "replay_hash": replay_hash, "looks": [{"hat": "straw_hat"}, {}]}, "result": null, "eligible": false, "sides": [side, null]}

## The see-through pip beside its slot, its faint name, the timer mark, and nothing left after.
func _view() -> void:
	var world := FakeWorld.new()
	var holder := Node3D.new()
	world.add_child(holder)
	var mine := Node3D.new()
	holder.add_child(mine)
	world.actors = {"p0": mine, "p1": Node3D.new()}
	root.add_child(world)
	var timer: Control = TimerBar.new()
	timer.size = Vector2(300, 66)
	root.add_child(timer)
	var points := PackedFloat32Array([0, 0, 0, 100, 0, 0, 200, 50, 0])
	var view: Node = View.new()
	root.add_child(view)
	_check(view.show_track(world, {"slot": "p0", "points": points, "duration_ticks": 2, "look": {}, "name": ""}, timer, 8, true), "the ghost shows")
	var spirit: Node3D = view.spirit
	_check(is_instance_valid(spirit) and spirit.get_parent() == holder, "beside the pips, under their parent")
	var face: Material = spirit.face_art.material
	var parts := spirit.find_children("*", "MeshInstance3D", true, false).filter(func(part: MeshInstance3D) -> bool: return part.visible and part.material_override != face)
	_check((face as ShaderMaterial).shader == View.GHOST_FACE and is_equal_approx(float((face as ShaderMaterial).get_shader_parameter("veil")), View.VEIL), "the face draws see-through at half strength")
	_check(not parts.is_empty() and parts.all(func(part: MeshInstance3D) -> bool: return part.material_override is BaseMaterial3D and part.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and part.material_override.albedo_color.a <= View.VEIL + 0.001), "and every other part")
	_check(parts.all(func(part: MeshInstance3D) -> bool: return not part.material_override.has_meta(Primitives.SHARED_META)), "never changing a material the live pips share")
	var again: Node = View.new()
	root.add_child(again)
	again.show_track(world, {"slot": "p0", "points": points, "duration_ticks": 2, "look": {}, "name": "Lee"}, null, 8, true)
	_check(again.name_badge.text == "Lee", "a named pair's player races by name")
	again.release()
	again.show_track(world, {"slot": "p0", "points": points, "duration_ticks": 2, "look": {}, "name": "", "developer": true}, null, 8, true)
	_check(again.name_badge.text == PlayerCopy.DUELS_GHOST_DEVELOPERS, "Our run races as Our run")
	again.release()
	again.queue_free()
	_check(not (spirit.get("ground_shadow") as Node3D).visible, "with no ground shadow")
	_check(view.name_badge.text == PlayerCopy.RACE_GHOST_RECORDED and view.name_badge.modulate.a < 1.0, "a pair that hides its names races as Recorded run, faintly")
	_check(is_equal_approx(timer.race_ratio, 0.25) and timer.find_child("RaceGhostMark", true, false) != null, "the timer marks where the raced turn finished")
	view.at_tick(2, true)
	_check(spirit.position.is_equal_approx(Vector3(2.0, 0.5, 0.0)), "the pip stands where the run stood at the turn's tick: %s" % spirit.position)
	view.at_tick(1, true)
	view.at_tick(2)
	_check(not spirit.position.is_equal_approx(Vector3(2.0, 0.5, 0.0)), "a tick at a time, the pip eases there")
	view.at_tick(99)
	_check(spirit.position.is_equal_approx(Vector3(2.0, 0.5, 0.0)), "a jump (a skipped memory wait) puts it there at once, never sliding across")
	view.at_tick(99, true)
	_check(spirit.position.is_equal_approx(Vector3(2.0, 0.5, 0.0)), "and waits at its finish")
	view.release()
	await process_frame
	_check(not is_instance_valid(spirit) and timer.race_ratio < 0.0 and timer.find_child("RaceGhostMark", true, false) == null, "released, nothing of it stays")
	view.queue_free()
	world.queue_free()
	timer.queue_free()
	await process_frame

func _clear() -> void:
	TheirRun.erase_owner(OWNER)
	for candidate: String in [DuelsClient.SAVE_PATH, DuelsClient.SAVE_PATH + ".tmp", DuelsClient.SAVE_PATH + ".bak"]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
