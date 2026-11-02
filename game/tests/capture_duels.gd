extends SceneTree
## Development tool, not a suite: captures the duel pages through the game's
## own screens (presentation/duels/), with example duels, names and times and
## no server. tests/ is never exported, so no player build has it. Needs a GPU
## (a rendered, not headless, run) at 1280x720, from a copy of the game whose
## window starts off screen:
##   godot --path <copy> --position -20000,-20000 --resolution 1280x720 --script res://tests/capture_duels.gd -- --out=<dir>
## Writes <dir>/duels-lobby.png, duels-lobby-empty.png, duel-in-progress.png,
## duel-waiting.png, duel-result-won.png, duel-result-checking.png,
## duel-ghost-result.png, duels-party.png, duels-start.png, duels-race.png,
## home-duels-row.png, duels-lobby-both-empty.png and duel-room-turn.png (a duel
## room's world with both members in their looks), each with --suffix=<text>
## added to its name when given. Every pip wears a look: yours (straw hat) and
## each other player's as a server with looks sends it.
const Client = preload("res://services/duels_client.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Snapshots = preload("res://presentation/kit/pip_snapshots.gd")
const Lobby = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const SlotLooks = preload("res://presentation/slot_looks.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const NOOR := "NNNNNNNNNNNNNNNNNNNNNN"
const LEE := "LLLLLLLLLLLLLLLLLLLLLL"
const SAM := "SSSSSSSSSSSSSSSSSSSSSS"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const NAMES := {ME: "You", MAYA: "Maya", FINN: "Finn", NOOR: "Noor", LEE: "Lee", SAM: "Sam"}
const T := 30
## What everyone else wears, as the server sends it.
const LOOKS := {MAYA: {"hat": "daisy"}, FINN: {"body": "tide"}, NOOR: {"hat": "seashell"}, LEE: {"hat": "seashell", "body": "tide"}, SAM: {"hat": "daisy"}}

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

## A duel as the server sends it, read through the client's own check.
func _duel(id: String, chapter: String, status: String, mine: Array, theirs: Array, extra: Dictionary = {}) -> Dictionary:
	var steps: int = Registry.definition(chapter).stages.size() * 2
	var wire := {"schema_version": 1, "duel_id": id.repeat(32 / id.length()), "kind": "friend", "board": chapter, "status": status, "steps": steps,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"sides": [{"members": [ME, MAYA], "you": true, "steps": mine[0], "ticks": mine[1] * T, "turn": mine[2], "finished": mine[0] == steps, "left": false, "check": "none", "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true, "looks": [{}, LOOKS[MAYA]]},
			{"members": theirs[3], "you": false, "steps": theirs[0], "ticks": theirs[1] * T, "turn": theirs[2], "finished": theirs[0] == steps, "left": false, "check": "none", "looks": theirs[3].map(func(id: String) -> Dictionary: return LOOKS.get(id, {}))}]}
	wire.merge(extra, true)
	var view := Client.valid_view(wire)
	if view.is_empty(): push_error("capture duel did not read: " + id)
	return view

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("CAPTURE needs a rendered run; headless draws nothing.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	# The server's offered items, as a wallet read sets them: every look below shows.
	Catalog.set_offered(["daisy", "seashell", "straw_hat", "tide"])
	Wardrobe.use_shared(Dressed.new())
	var lighthouse := Registry.LIGHTHOUSE_V2
	var rolling := Registry.ROLLING_HOME
	var relay := Registry.RELAY
	var running := _duel("1a", lighthouse, "running", [3, 108, 0], [2, 92, 1, [FINN, NOOR]])
	var partner_turn := Client.valid_view({"schema_version": 1, "duel_id": "2b".repeat(16), "kind": "ghost", "board": rolling, "status": "running", "steps": 4, "created_ms": 1, "accepted_ms": 2, "updated_ms": 2, "mine": 0,
		"ghost": {"source": "board", "ticks": 195 * T, "rank": 1, "names": null}, "result": null, "eligible": false,
		"sides": [{"members": [ME, MAYA], "you": true, "steps": 2, "ticks": 54 * T, "turn": 1, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": "", "hosting": true, "looks": [{}, LOOKS[MAYA]]}, null]})
	var won := _duel("3c", relay, "decided", [4, 222, null], [4, 246, null, [LEE, SAM]], {"result": {"outcome": "won", "reason": "faster", "margin_ticks": 24 * T, "decided_ms": 9}})
	var challenge_in := _duel("4d", relay, "challenged", [0, 0, null], [0, 0, null, [FINN, NOOR]], {"mine": 1})
	challenge_in.mine = 1
	var swapped: Array = [challenge_in.sides[1], challenge_in.sides[0]]
	swapped[0].you = false
	swapped[1].you = true
	challenge_in.sides = swapped
	var challenge_out := _duel("5e", rolling, "challenged", [0, 0, null], [0, 0, null, [LEE, SAM]])
	var lobby_data := {"party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null, "partner_look": LOOKS[MAYA]}, "duels": [running, partner_turn, won, challenge_in, challenge_out], "limits": {"friend": 3, "ghost": 3}}
	var lobby := Lobby.new()
	lobby.me = ME
	lobby.name_of = _name_of
	lobby.boost_percent = 10
	root.add_child(lobby)
	lobby.show_lobby(lobby_data)
	await _save("duels-lobby")
	# The duel in progress, your move, then your partner's.
	var page := DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = running
	lobby.open_overlay(page)
	await _save("duel-in-progress")
	var level := _duel("1a", lighthouse, "running", [4, 140, 1], [4, 152, 0, [FINN, NOOR]])
	page.show_duel(level)
	await _save("duel-waiting")
	page.close()
	# Results.
	var result := ResultPage.new()
	result.me = ME
	result.name_of = _name_of
	result.view = won
	result.pay = {"turns": 2, "plain": 222, "blooms": 0, "duel": 112, "duel_percent": 50, "boost": 22, "boost_percent": 10, "total": 356}
	result.win_bonus = {"amount": 250, "counted": true, "reason": ""}
	lobby.open_overlay(result)
	await _save("duel-result-won")
	result.close()
	var checking := ResultPage.new()
	checking.me = ME
	checking.name_of = _name_of
	checking.view = _duel("6f", lighthouse, "running", [12, 218, null], [12, 231, null, [FINN, NOOR]], {})
	lobby.open_overlay(checking)
	await _save("duel-result-checking")
	checking.close()
	var ghost_won := Client.valid_view({"schema_version": 1, "duel_id": "7a".repeat(16), "kind": "ghost", "board": relay, "status": "decided", "steps": 4, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0,
		"ghost": {"source": "developer", "ticks": 230 * T, "rank": null, "names": null}, "result": {"outcome": "won", "reason": "faster", "margin_ticks": 9 * T}, "eligible": false,
		"sides": [{"members": [ME, MAYA], "you": true, "steps": 4, "ticks": 221 * T, "turn": null, "finished": true, "left": false, "check": "none", "room_id": ROOM, "invite_code": "", "hosting": true}, null]})
	var ghost_page := ResultPage.new()
	ghost_page.me = ME
	ghost_page.name_of = _name_of
	ghost_page.view = ghost_won
	ghost_page.pay = {"turns": 2, "plain": 222, "blooms": 111, "duel": 0, "duel_percent": 0, "boost": 0, "boost_percent": 0, "total": 333}
	lobby.open_overlay(ghost_page)
	await _save("duel-ghost-result")
	ghost_page.close()
	# The party page, with an invite and your friends to ask.
	var party := PartyPage.new()
	party.name_of = _name_of
	party.party = {"partner": MAYA, "intact": true, "invites_in": [FINN], "invite_out": null, "partner_look": LOOKS[MAYA]}
	party.friends = [{"id": MAYA, "name": "Maya"}, {"id": NOOR, "name": "Noor"}, {"id": LEE, "name": "Lee"}]
	lobby.open_overlay(party)
	await _save("duels-party")
	party.close()
	# Start a duel, with a pair and a chapter chosen.
	var start := ChallengePage.new()
	start.friends = [{"id": FINN, "name": "Finn"}, {"id": LEE, "name": "Lee"}, {"id": SAM, "name": "Sam"}]
	var open: Array = []
	for key: String in ChapterUnlocks.chain(): if Registry.definition(key).has("stages"): open.append(key)
	start.chapters = open
	lobby.open_overlay(start)
	await process_frame
	start._pick_friend(FINN)
	start._pick_chapter(lighthouse)
	await _save("duels-start")
	start.close()
	# Race a recorded run.
	var race := GhostPage.new()
	race.chapters = open
	lobby.open_overlay(race)
	var boards: Array = []
	for key: String in open:
		var top: Array = [] if key != lighthouse else [{"entry_id": "e1".repeat(16), "ticks": 196 * T, "rank": 1, "names": null}, {"entry_id": "e2".repeat(16), "ticks": 202 * T, "rank": 2, "names": null}]
		boards.append({"board": key, "developer": 60 * T + key.length() * 90, "top": top})
	race.show_ghosts(boards)
	await _save("duels-race")
	race.close()
	lobby.show_lobby({"party": {"partner": null, "intact": false, "invites_in": [MAYA], "invite_out": null}, "duels": [], "limits": {"friend": 3, "ghost": 3}})
	await _save("duels-lobby-empty")
	# Both lists empty, with the owner's picked arts.
	lobby.show_lobby({"party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [], "limits": {"friend": 3, "ghost": 3}})
	await _save("duels-lobby-both-empty")
	lobby.close()
	await process_frame
	await _home()
	await _room()
	print("CAPTURE DONE")
	quit(0)

func _home() -> void:
	var back := ColorRect.new()
	back.color = Color("2f5d52")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var menu := HomeMenu.new()
	holder.add_child(menu)
	var none := func() -> void: pass
	menu.build({"play": func(_button: Button) -> void: pass, "solo": none, "friends": none, "duels": none, "replays": none, "invite": none, "whats_new": none, "settings": none, "full_journey": none}, preload("res://assets/fonts/nunito.ttf"))
	menu.show_duels(true)
	await _save("home-duels-row")
	holder.queue_free()
	back.queue_free()
	await process_frame

## A duel room's turn: the chapter's world, each slot dressed as the room screen
## dresses it (presentation/slot_looks.gd live) from a duel room's snapshot and
## the partner's look as a room read reports it (services/turn_looks.gd).
func _room() -> void:
	var looks_path := "user://capture-duel-room-looks.json"
	var store: RefCounted = TurnLooks.new(looks_path)
	TurnLooks.use_shared(store)
	store.note_member(MAYA, LOOKS[MAYA])
	var key := Registry.RELAY
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	GraphicsPolicy.apply(world, {"graphics_quality": "balanced"})
	world.wear_slots(SlotLooks.live({"player_slot": "p0", "host_id": ME, "guest_id": MAYA, "duel": true}))
	world.load_level(Registry.definition(key))
	await _save("duel-room-turn", 60)
	world.queue_free()
	TurnLooks.use_shared(null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(looks_path))
	await process_frame

## Saves the window once every still pip is drawn and `frames` more have passed.
func _save(name: String, frames: int = 30, suffixed: bool = true) -> void:
	var waited := 0
	while (Snapshots.pending() > 0 or waited < frames) and waited < 600:
		await process_frame
		waited += 1
	await RenderingServer.frame_post_draw
	var path := "%s/%s%s.png" % [_out, name, _suffix if suffixed else ""]
	print("SAVED %s %s" % [path, error_string(root.get_texture().get_image().save_png(path))])
