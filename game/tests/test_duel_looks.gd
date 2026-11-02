extends SceneTree
## Looks on the duel pages: every pip wears its player's look. This player's
## own pip wears their own look wherever they sit in their pair (first or
## second), partners and the other pair wear what the server sent
## (services/duels_client.gd keeps `looks` and `party.partner_look`), a board
## ghost its row's looks, and services/outfit.gd cleans every one, so an item
## this phone is not offered never shows. A server without looks reads as the
## default. Friends no duel reply speaks of (the party page's rows, Start a
## duel's list) wear the look this phone last heard them wear in a room.
## Synthetic ids only.
const Client = preload("res://services/duels_client.gd")
const DuelModel = preload("res://services/duel_model.gd")
const Kit = preload("res://presentation/duels/duel_kit.gd")
const Lobby = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const TurnLooks = preload("res://services/turn_looks.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const NOOR := "NNNNNNNNNNNNNNNNNNNNNN"
const ROOM := "RRRRRRRRRRRRRRRRRRRRRR"
const BOARD := "sleeping-lighthouse@2"
const DUEL := "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"
const MINE := {"hat": "straw_hat"}
const MAYA_LOOK := {"hat": "daisy"}
const FINN_LOOK := {"body": "tide"}
const NOOR_LOOK := {"hat": "seashell"}

var checks := 0
var failures := 0

class Dressed extends RefCounted:
	func active_look() -> Dictionary: return {"hat": "straw_hat"}

func _initialize() -> void: _run.call_deferred()
func _check(okay: bool, message: String) -> void:
	checks += 1
	if not okay:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _name_of(id: Variant) -> String:
	return {ME: PlayerCopy.DUEL_YOU, MAYA: "Maya", FINN: "Finn", NOOR: "Noor"}.get(id, "")

## A running friend duel as a server with looks sends it. `second`: this player sits second in their pair.
func _wire(second: bool = false, overrides: Dictionary = {}) -> Dictionary:
	var own_members: Array = [MAYA, ME] if second else [ME, MAYA]
	var own_looks: Array = [MAYA_LOOK, {"hat": "lantern"}] if second else [{"hat": "lantern"}, MAYA_LOOK]
	var view := {"schema_version": 1, "duel_id": DUEL, "kind": "friend", "board": BOARD, "status": "running", "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"sides": [
			{"members": own_members, "you": true, "steps": 3, "ticks": 3240, "turn": 0, "finished": false, "left": false, "check": "none", "room_id": ROOM, "invite_code": "abcdefabcdefabcdefab", "hosting": true, "looks": own_looks},
			{"members": [FINN, null], "you": false, "steps": 2, "ticks": 2760, "turn": 1, "finished": false, "left": false, "check": "none", "looks": [FINN_LOOK, NOOR_LOOK]}]}
	view.merge(overrides, true)
	return view

func _run() -> void:
	Catalog.set_offered(["daisy", "seashell", "straw_hat", "tide"])
	Wardrobe.use_shared(Dressed.new())
	_client()
	_kit()
	await _pages()
	Wardrobe.use_shared(null)
	Catalog.set_offered([])
	print("AFTER YOU DUEL LOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _client() -> void:
	var view := Client.valid_view(_wire())
	_check(view.sides[0].looks == [{"hat": "lantern"}, MAYA_LOOK] and view.sides[1].looks == [FINN_LOOK, NOOR_LOOK], "each side keeps its members' looks in members order")
	_check(DuelModel.looks(view, 1) == [FINN_LOOK, NOOR_LOOK] and DuelModel.members(view, 1) == [FINN, null], "the model hands a side's members and looks to the pages, a hidden member's look too")
	var old := _wire()
	for side: Dictionary in old.sides: side.erase("looks")
	var plain := Client.valid_view(old)
	_check(not plain.is_empty() and plain.sides[0].looks == [{}, {}] and DuelModel.looks(plain, 1) == [{}, {}], "a server without looks reads, every pip in the default")
	var odd := _wire()
	odd.sides[1].looks = ["hat", 3]
	_check(Client.valid_view(odd).sides[1].looks == [{}, {}], "looks that are not Dictionaries read as the default and never refuse the duel")
	var race := Client.valid_view(_wire(false, {"kind": "ghost", "ghost": {"source": "board", "ticks": 3000, "rank": 1, "names": null, "looks": [NOOR_LOOK, {}]}, "sides": [_wire().sides[0], null]}))
	_check(DuelModel.looks(race, 1) == [NOOR_LOOK, {}] and DuelModel.members(race, 1) == [null, null], "a board ghost wears its row's looks")
	var lobby := Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null, "partner_look": MAYA_LOOK}, "duels": []})
	_check(lobby.party.partner_look == MAYA_LOOK, "the lobby keeps the partner's look")
	_check(Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": []}).party.partner_look == {}, "and the default from a server without looks")

## The pip pair: own by id, wherever the player sits; the rest cleaned.
func _kit() -> void:
	for second: bool in [false, true]:
		var view := Client.valid_view(_wire(second))
		var pair := Kit.pips(Vector2(30, 40), DuelModel.members(view, 0), ME, DuelModel.looks(view, 0))
		root.add_child(pair)
		var own: PipAvatar = pair.get_child(1 if second else 0)
		var partner: PipAvatar = pair.get_child(0 if second else 1)
		_check(own.own and own.outfit == MINE, "sitting %s, your own pip wears your own look: %s" % ["second" if second else "first", own.outfit])
		_check(not partner.own and partner.outfit == MAYA_LOOK, "and your partner's pip theirs: %s" % [partner.outfit])
		pair.free()
	var stray := Kit.pip(Vector2(30, 40), Kit.SECOND_PIP, false, {"hat": "lantern", "body": "tide"})
	_check(stray.outfit == {"body": "tide"}, "an item this phone is not offered never shows: %s" % [stray.outfit])
	stray.free()
	var nobody := Kit.pips(Vector2(30, 40))
	root.add_child(nobody)
	_check(nobody.get_children().all(func(pip: Node) -> bool: return not pip.own and pip.outfit.is_empty()), "a pair with nobody known wears the default")
	nobody.free()

func _worn(node: Node) -> Array:
	return node.find_children("*", "", true, false).filter(func(child: Node) -> bool: return child is PipAvatar).map(func(pip: PipAvatar) -> Dictionary: return MINE if pip.own and pip.outfit == MINE else pip.outfit)

func _pages() -> void:
	var view := Client.valid_view(_wire(true))
	var challenge := _wire(false, {"duel_id": "d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1", "status": "challenged", "mine": 1})
	challenge.sides = [_wire().sides[1].merged({"you": false}, true), _wire().sides[0].merged({"you": true}, true)]
	var lobby_data := Client.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null, "partner_look": MAYA_LOOK}, "duels": [_wire(true), challenge]})
	var lobby := Lobby.new()
	lobby.me = ME
	lobby.name_of = _name_of
	root.add_child(lobby)
	lobby.show_lobby(lobby_data)
	await process_frame
	var party: Node = lobby.find_child("DuelsPartyButton", true, false).get_parent()
	_check(_worn(party) == [MINE, MAYA_LOOK], "Your party: your pip in your look and your partner's in theirs: %s" % [_worn(party)])
	var tile: Node = lobby.find_child("DuelsTiles", true, false).get_child(0)
	_check(_worn(tile) == [MAYA_LOOK, MINE, FINN_LOOK, NOOR_LOOK], "a tile dresses both pairs, you in your own look in your own seat: %s" % [_worn(tile)])
	var open: Node = lobby.find_child("DuelsOpenList", true, false)
	_check(_worn(open) == [FINN_LOOK, NOOR_LOOK], "a challenge to you shows the other pair in their looks: %s" % [_worn(open)])
	# The duel page: both side cards and the pair beside your card.
	var page := DuelPage.new()
	page.me = ME
	page.name_of = _name_of
	page.view = view
	lobby.open_overlay(page)
	await process_frame
	_check(_worn(page.find_child("DuelSide0", true, false)) == [MAYA_LOOK, MINE] and _worn(page.find_child("DuelSide1", true, false)) == [FINN_LOOK, NOOR_LOOK], "the duel page dresses every pip on both side cards")
	var cards: Array = _worn(page)
	_check(cards.count(MINE) == 2 and cards.count(MAYA_LOOK) == 2 and not cards.has({"hat": "lantern"}), "and your own pair beside your card: %s" % [cards])
	page.close()
	# The result page, a ghost race against a board run in its looks.
	var race := Client.valid_view(_wire(true, {"kind": "ghost", "status": "decided", "ghost": {"source": "board", "ticks": 3000, "rank": 1, "names": null, "looks": [NOOR_LOOK, {}]},
		"result": {"outcome": "won", "reason": "faster", "margin_ticks": 30}, "sides": [_wire(true).sides[0].merged({"steps": 12, "finished": true}, true), null]}))
	var result := ResultPage.new()
	result.me = ME
	result.name_of = _name_of
	result.view = race
	lobby.open_overlay(result)
	await process_frame
	_check(_worn(result.find_child("ResultSide0", true, false)) == [MAYA_LOOK, MINE] and _worn(result.find_child("ResultSide1", true, false)) == [NOOR_LOOK, {}], "the result page dresses your pair and the recorded run's: %s" % [_worn(result)])
	result.close()
	# The party page: your slot and your partner's.
	var party_page := PartyPage.new()
	party_page.name_of = _name_of
	party_page.party = lobby_data.party
	party_page.friends = [{"id": NOOR, "name": "Noor"}]
	lobby.open_overlay(party_page)
	await process_frame
	var worn := _worn(party_page)
	_check(worn.size() >= 2 and worn[0] == MINE and worn[1] == MAYA_LOOK, "the party page: you in your look, your partner in theirs: %s" % [worn])
	party_page.close()
	# Friends: the look this phone last heard them wear in a room, the default for one it never did.
	var looks_path := "user://test-duel-looks-turns-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	var store: RefCounted = TurnLooks.new(looks_path)
	TurnLooks.use_shared(store)
	store.note_member(NOOR, NOOR_LOOK)
	var friends_page := PartyPage.new()
	friends_page.name_of = _name_of
	friends_page.party = {"partner": null, "intact": false, "invites_in": [FINN], "invite_out": null, "partner_look": {}}
	friends_page.friends = [{"id": NOOR, "name": "Noor"}]
	lobby.open_overlay(friends_page)
	await process_frame
	_check(_worn(friends_page.find_child("Friend_" + NOOR.left(6), true, false)) == [NOOR_LOOK] and _worn(friends_page.find_child("Friend_" + FINN.left(6), true, false)) == [{}], "a friend's row wears their last seen look, one never seen the default")
	friends_page.close()
	var start := ChallengePage.new()
	start.friends = [{"id": NOOR, "name": "Noor"}]
	lobby.open_overlay(start)
	await process_frame
	_check(_worn(start.find_child("Pair_" + NOOR.left(6), true, false)) == [NOOR_LOOK, {}], "Start a duel shows the friend in their last seen look: %s" % [_worn(start)])
	start.close()
	TurnLooks.use_shared(null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(looks_path))
	lobby.queue_free()
	await process_frame
