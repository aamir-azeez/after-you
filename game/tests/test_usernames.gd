extends SceneTree
## Usernames (services/usernames.gd):
## - the shared vectors (also run by backend/test/usernames.test.ts) answer the
##   same here, and the player's own short name is theirs to take;
## - the friends page turns usernames on, keeps the own one across a reload,
##   names every row by its username (a request too) and makes the friend code
##   friend-<lowercase>; a page without the key turns them off;
## - the friends client takes the new keys only in their shape;
## - the name prompt's username mode: no anonymous row, the rules' words, the
##   friend code line, a suggestion only into an empty field, and the server's
##   refusal on the card;
## - the flow: opens once a run for a player with none, sends the shown price,
##   keeps the name the server confirmed, and closes a card it opened by itself
##   when the player turns out to have one.
const Usernames = preload("res://services/usernames.gd")
const DisplayNames = preload("res://services/display_names.gd")
const FriendsClient = preload("res://services/friends_client.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const ShareCodes = preload("res://services/share_codes.gd")
const Prompt = preload("res://presentation/display_name_prompt.gd")
const Flow = preload("res://presentation/display_name_flow.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

const VECTORS := "res://tests/fixtures/display_names/username_vectors.json"
# Synthetic ids only.
const BASE := "https://example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const MAYA := "bbbbbbbbbbbbbbbbbbbbbb"
const SAM := "cccccccccccccccccccccc"

var checks := 0
var failures := 0
var viewport: SubViewport
var page: Control
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"
	var busy := false

class Saves extends RefCounted:
	var data := {"settings": {"reduced_motion": true}}

class Host extends Node:
	var api: Node
	var saves := Saves.new()
	var toasts: Array = []
	var soundscape: Node = null
	func _leaderboards_offered() -> bool: return false
	func _names_scope() -> Dictionary: return {"server": str(api.base_url), "owner": str(api.player_id)}
	func _toast(text: String) -> void: toasts.append(text)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 720)
	root.add_child(viewport)
	page = Control.new()
	page.size = Vector2(1600, 720)
	viewport.add_child(page)
	_vectors()
	_friends_page()
	_client_shapes()
	await _prompt()
	await _flow()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	DisplayNames.use_shared(null)
	print("AFTER YOU USERNAMES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _vectors() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VECTORS))
	_check(parsed is Dictionary and parsed.get("cases") is Array and parsed.cases.size() > 20, "The shared vectors load")
	for case: Variant in parsed.get("cases", []):
		var answer := Usernames.problem(str(case[0]))
		_check((answer if not answer.is_empty() else "ok") == str(case[1]), "Vector %s answers %s, not %s" % [case[0], case[1], answer])
	_check(Usernames.problem("aamir", "aamir").is_empty() and Usernames.problem("Aamir", "aamir").is_empty(), "The player's own short name is theirs to take")
	_check(Usernames.problem("aamir", "maple") == "username_reserved", "Someone else's is not")
	_check(Usernames.valid_remote("TheBlueBeanie") and not Usernames.valid_remote("ab") and not Usernames.valid_remote(null), "A name from the server is checked for shape")

func _friends_page() -> void:
	var path := _path("page")
	var store: RefCounted = DisplayNames.new(path)
	DisplayNames.use_shared(store)
	var friends := [
		{"player_id": MAYA, "request_id": MAYA, "status": "incoming", "online": false, "expires_after_seconds": 0, "join_available": false, "display_name": null, "username": "Maple.Leaf"},
		{"player_id": SAM, "request_id": SAM, "status": "accepted", "online": false, "expires_after_seconds": 0, "join_available": false, "display_name": "Sam", "username": "sam_99"},
	]
	store.take_friends_page(BASE, ME, {"display_name": "TheBlueBeanie", "username": "TheBlueBeanie", "friends": friends})
	_check(store.usernames_on(BASE, ME) and store.username(BASE, ME) == "TheBlueBeanie", "A page with the key turns usernames on and keeps the own one")
	var nicknames := FriendNicknames.new(_path("nicknames"))
	_check(nicknames.display_name(BASE, ME, MAYA) == "Maple.Leaf", "A request is named by its username through the one name path")
	_check(nicknames.display_name(BASE, ME, SAM) == "Sam", "A friend's display name still wins where it is served")
	var again: RefCounted = DisplayNames.new(path)
	_check(again.usernames_on(BASE, ME) and again.username(BASE, ME) == "TheBlueBeanie", "Both survive a reload")
	store.take_friends_page(BASE, ME, {"display_name": "TheBlueBeanie", "friends": []})
	_check(not store.usernames_on(BASE, ME), "A page without the key turns usernames off")
	DisplayNames.use_shared(null)

func _client_shapes() -> void:
	var good := {"schema_version": 1, "friend_code": ME, "refresh_after_seconds": 30, "shared_room": null, "display_name": null, "username": "TheBlueBeanie",
		"friends": [{"player_id": MAYA, "request_id": MAYA, "status": "incoming", "online": false, "expires_after_seconds": 0, "join_available": false, "display_name": null, "username": "Maple.Leaf"}]}
	_check(FriendsClient.valid_page(good, ME), "A page with usernames is taken")
	var long := good.duplicate(true)
	long.username = "x".repeat(65)
	_check(not FriendsClient.valid_page(long, ME), "A username past the wire shape is refused")
	var extra := good.duplicate(true)
	extra.friends[0]["surprise"] = 1
	_check(not FriendsClient.valid_page(extra, ME), "Rows still have exactly their keys")
	_check(ShareCodes.format(ShareCodes.FRIEND, Usernames.key("TheBlueBeanie")) == "friend-thebluebeanie", "The friend code is the lowercase name")

func _prompt() -> void:
	var saved: Array = []
	var answer := {"closed": false, "code": "username_taken"}
	var modal: Control = Prompt.open(page, {"username": true, "own": {"choice": "typed", "name": "", "fold": true},
		"save": func(choice: String, name: String) -> Dictionary:
			saved.append([choice, name])
			await process_frame
			return answer})
	await _frames(3)
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false)
	_check(modal.title_label.text == PlayerCopy.USERNAME_ASK, "The card asks for a username")
	_check(modal.find_child("DisplayNameAnonymous", true, false) == null and modal.find_child("DisplayNamePlatform", true, false) == null, "No anonymous or platform row")
	prompt.set_suggestion("Maple.Leaf")
	_check(prompt.field.text == "Maple.Leaf", "A suggestion fills the empty field")
	_check((modal.find_child("UsernameCode", true, false) as Label).text == PlayerCopy.USERNAME_CODE % "maple.leaf", "The friend code line shows the lowercase name")
	prompt.set_suggestion("Other")
	_check(prompt.field.text == "Maple.Leaf", "A later suggestion never replaces what is there")
	prompt.field.text = "blue..bean"
	prompt._typed("")
	prompt._save()
	await _frames(2)
	_check(saved.is_empty() and prompt._error.text == PlayerCopy.USERNAME_ERRORS.symbols, "A name the rules refuse is said on the card and never sent")
	prompt.field.text = "TheBlueBeanie"
	prompt._typed("")
	prompt._save()
	await _frames(4)
	_check(saved == [["typed", "TheBlueBeanie"]], "Save sends the typed name")
	_check(is_instance_valid(modal) and prompt._error.text == PlayerCopy.USERNAME_ERRORS.username_taken, "A taken name is said on the card, which stays open")
	_check(Prompt.choice_cost({"price": 1000}, {"choice": "typed", "name": "TheBlueBeanie", "fold": true}, "typed", "theblueBEANIE") == 0, "Capitals alone cost nothing")
	_check(Prompt.choice_cost({"price": 1000}, {"choice": "typed", "name": "TheBlueBeanie", "fold": true}, "typed", "Other.Name") == 1000, "A new name costs the price")
	modal.close()
	await _frames(2)

func _flow() -> void:
	var store: RefCounted = DisplayNames.new(_path("flow"))
	DisplayNames.use_shared(store)
	var api := Api.new()
	var host := Host.new()
	host.api = api
	host.add_child(api)
	root.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	var sent: Array = []
	var server := {"username": null}
	flow.username_transport = func(method: int, _path: String, body: Dictionary) -> Dictionary:
		sent.append([method, body])
		await process_frame
		if method == HTTPClient.METHOD_GET: return {"ok": true, "data": {"schema_version": 1, "username": server.username, "suggestion": "Maple.Leaf"}}
		return {"ok": true, "data": {"schema_version": 1, "username": body.username}}
	_check(not flow.maybe_ask(page), "Usernames off: no prompt")
	store.set_enabled(BASE, ME, true)
	store.set_usernames(BASE, ME, true)
	_check(flow.maybe_ask(page, true), "Usernames on and none yet: the prompt opens")
	await _frames(4)
	var modal: Control = page.find_child("DisplayNameModal", true, false)
	var prompt: Node = modal.find_child("DisplayNamePrompt", true, false)
	_check(prompt.field.text == "Maple.Leaf", "The server's suggestion fills the field")
	prompt.field.text = "TheBlueBeanie"
	prompt._typed("")
	prompt._save()
	await _frames(4)
	_check(sent.back() == [HTTPClient.METHOD_PUT, {"schema_version": 1, "username": "TheBlueBeanie"}], "Save sends the name (no price while the shop is off)")
	_check(store.username(BASE, ME) == "TheBlueBeanie" and (not is_instance_valid(modal) or modal.is_queued_for_deletion()), "The confirmed name is kept and the card closes")
	_check(host.toasts.is_empty(), "A saved card says nothing more")
	_check(not flow.maybe_ask(page), "A player with a username is not asked again")
	# A new install that never heard its name: the card it opened by itself closes once the server says.
	store.set_username(BASE, ME, "")
	flow._asked_username = false
	server.username = "TheBlueBeanie"
	_check(flow.maybe_ask_username(page, true), "Asked again on a phone that knows no name")
	await _frames(6)
	var again: Control = page.find_child("DisplayNameModal", true, false)
	_check(again == null or again.is_queued_for_deletion(), "The card closes when the server says the player has one")
	_check(store.username(BASE, ME) == "TheBlueBeanie" and host.toasts.is_empty(), "The name is kept and nothing is said")
	host.queue_free()
	DisplayNames.use_shared(null)
	await _frames(2)

func _frames(count: int) -> void:
	for i in range(count): await process_frame

func _path(label: String) -> String:
	var path := "user://test-usernames-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
