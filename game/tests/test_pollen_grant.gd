extends SceneTree
## The Full Journey monthly Pollen on this phone (services/pollen_grant.gd,
## presentation/pollen_grant_card.gd, presentation/full_journey_benefits.gd and
## the grant read in services/pollen_client.gd), through a fake transport:
## - the wallet answer's grant part is kept only in the contract's shape;
## - "Your monthly Pollen arrived" shows once per instalment, only while the
##   grant is on and only for a recent one, and says the month and what next
##   month pays (its board, Home and first taps: test_full_journey_board.gd);
## - the Full Journey card lists the chapters first, then the room boost, then
##   the monthly Pollen, and the Pollen panels only while the server pays them;
## - a phone with Full Journey reads the wallet for the grant once a launch and
##   then at most every few hours; a free player's phone never does.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const Client = preload("res://services/pollen_client.gd")
const GrantCard = preload("res://presentation/pollen_grant_card.gd")
const Benefits = preload("res://presentation/full_journey_benefits.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")

# Synthetic ids only.
const SERVER := "https://pollen.example.test"
const ME := "aaaaaaaaaaaaaaaaaaaaaa"
const DAY_MS := 86400000

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Api extends Node:
	var base_url := "https://pollen.example.test"
	var player_id := "aaaaaaaaaaaaaaaaaaaaaa"

## A transport that answers from a queue, one frame later.
class Fake extends RefCounted:
	var tree: SceneTree
	var sent: Array = []
	var replies: Array = []
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true)})
		await tree.process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "code": "connection_interrupted"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_checked()
	_cards()
	await _card_view()
	_benefits()
	await _client_reads()
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	PollenGrant.use_shared(null)
	print("AFTER YOU POLLEN GRANT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _path(label: String) -> String:
	var path := "user://test-pollen-grant-%s-%s.json" % [label, Crypto.new().generate_random_bytes(6).hex_encode()]
	_paths.append(path)
	return path

static func _now() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

## A wallet answer with the grant part, as the server sends it (numbers as floats).
static func _answer(months: int, next: int, latest_key: String = "", amount: int = 0, at: int = -1) -> Dictionary:
	var grant := {"months": float(months), "next": float(next), "top": 12000.0}
	if not latest_key.is_empty(): grant["latest"] = {"key": latest_key, "amount": float(amount), "at": float(at if at >= 0 else _now())}
	return {"schema_version": 1.0, "balance": float(amount), "earned": float(amount), "bank": 12.0, "grant": grant}

func _checked() -> void:
	var answer := _answer(1, 4750, "grant:1790000000000:1", 4500)
	_check(PollenGrant.checked_grant(answer.grant) == {"months": 1, "next": 4750, "top": 12000, "latest": {"key": "grant:1790000000000:1", "amount": 4500, "at": int(answer.grant.latest.at)}}, "A grant part is kept")
	_check(not PollenGrant.checked_grant(_answer(31, 12000, "grant:lifetime", 4500).grant).is_empty(), "The Lifetime thank-you key is kept")
	for broken: Dictionary in [{"months": 1.0, "next": 0.0, "top": 12000.0}, {"months": 1.0, "next": 13000.0, "top": 12000.0}, {"months": -1.0, "next": 4500.0, "top": 12000.0},
			{"months": 1.0, "next": 4750.0, "top": 12000.0, "latest": {"key": "turn:x", "amount": 4500.0, "at": 1.0}}, {"months": 1.0, "next": 4750.0, "top": 12000.0, "latest": {"key": "grant:1:1", "amount": 0.0, "at": 1.0}}, {"months": 1.5, "next": 4750.0, "top": 12000.0}]:
		_check(PollenGrant.checked_grant(broken).is_empty(), "A broken grant part is not kept: " + str(broken))

func _cards() -> void:
	var store := PollenGrant.new(_path("cards"))
	store.note_view(SERVER, ME, _answer(1, 4750, "grant:1790000000000:1", 4500))
	_check(store.pending(SERVER, ME).is_empty(), "No card while the grant is off")
	store.set_enabled(SERVER, ME, true)
	var card: Dictionary = store.pending(SERVER, ME)
	_check(card == {"key": "grant:1790000000000:1", "amount": 4500, "next": 4750, "top": 12000}, "A new instalment has its card: " + str(card))
	store.mark_shown(SERVER, ME, card.key)
	_check(store.pending(SERVER, ME).is_empty(), "Once shown, it never shows again")
	var reloaded := PollenGrant.new(store.path)
	_check(reloaded.pending(SERVER, ME).is_empty() and reloaded.ladder(SERVER, ME).next == 4750, "That survives a restart, with the ladder")
	reloaded.note_view(SERVER, ME, _answer(2, 5000, "grant:1790000000000:2", 4750))
	_check(reloaded.pending(SERVER, ME).amount == 4750, "Next month's instalment has its own card")
	reloaded.note_view(SERVER, ME, _answer(3, 5250, "grant:1790000000000:3", 5000, _now() - 40 * DAY_MS))
	_check(reloaded.pending(SERVER, ME).is_empty(), "An old instalment (a new install, a long absence) is not news")
	_check(not reloaded.note_view(SERVER, ME, {"schema_version": 1.0, "balance": 0.0}), "A wallet answer with no grant part changes nothing")

func _card_view() -> void:
	_check(GrantCard.amount_text(4750) == "+4,750", "The big amount")
	_check(GrantCard.month_line({"key": "grant:1790000000000:2", "amount": 4750, "next": 5000, "top": 12000, "months": 2}) == "From Full Journey, month 2 of your ladder.\nNext month: 5,000.", "The month line")
	_check(GrantCard.month_line({"key": "grant:1790000000000:1", "amount": 4500, "next": 4750, "top": 12000, "months": 0}) == PlayerCopy.POLLEN_GRANT_NEXT % "4,750", "A month count below the instalment (a refund) names no month")
	_check(GrantCard.month_line({"key": "grant:lifetime", "amount": 4500, "next": 12000, "top": 12000, "months": 31}) == PlayerCopy.POLLEN_GRANT_LIFETIME, "The Lifetime thank you names no month")
	for line: String in [PlayerCopy.POLLEN_GRANT_TITLE, PlayerCopy.POLLEN_GRANT_MONTH, PlayerCopy.POLLEN_GRANT_LIFETIME, PlayerCopy.POLLEN_GRANT_NEXT, PlayerCopy.POLLEN_GRANT_WARDROBE, PlayerCopy.POLLEN_GRANT_DONE,
			PlayerCopy.FULL_JOURNEY_ROOM_BOOST, PlayerCopy.FULL_JOURNEY_ROOM_BOOST_NOTE, PlayerCopy.FULL_JOURNEY_GRANT, PlayerCopy.FULL_JOURNEY_GRANT_TOP, PlayerCopy.FULL_JOURNEY_GRANT_NOTE,
			PlayerCopy.FULL_JOURNEY_LADDER_NEXT, PlayerCopy.FULL_JOURNEY_LADDER_BY, PlayerCopy.FULL_JOURNEY_LADDER_TOP]:
		_check(not line.contains("-") and not line.contains("—") and not line.contains("–"), "No dashes: " + line)
	var parent := Control.new()
	parent.size = Vector2(1280, 720)
	root.add_child(parent)
	var card: Control = GrantCard.open(parent, {"key": "grant:1790000000000:2", "amount": 4750, "next": 5000, "top": 12000, "months": 2})
	await process_frame
	var texts: Array = card.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(PlayerCopy.POLLEN_GRANT_TITLE in texts and "+4,750" in texts and "From Full Journey, month 2 of your ladder.\nNext month: 5,000." in texts, "The card says what arrived and the ladder: " + str(texts))
	_check(card.find_child("PollenGrantWardrobe", true, false) == null, "No Wardrobe to open: Done alone")
	var done := card.find_child("PollenGrantDone", true, false) as Button
	_check(done != null and done.text == PlayerCopy.POLLEN_GRANT_DONE, "Done closes it")
	if done != null: done.pressed.emit()
	for i in range(20): await process_frame
	_check(not is_instance_valid(card) or not card.is_inside_tree(), "Done closes the card")
	parent.queue_free()
	await process_frame

func _benefits() -> void:
	var all := Benefits.content(true, true)
	_check(all.intro == PackedStringArray([PlayerCopy.SUBSCRIPTION_PURPOSE, PlayerCopy.COOPERATIVE_HOST_ACCESS]), "Chapters first: " + str(all.intro))
	_check(all.panels.map(func(panel: Dictionary) -> String: return panel.title) == [PlayerCopy.FULL_JOURNEY_ROOM_BOOST, "4,500 Pollen a month, growing every month you stay"], "then the room boost, then the monthly Pollen: " + str(all.panels))
	_check(Benefits.content(true, true, {"months": 6, "next": 6000, "top": 12000}).panels[1].title == "6,000 Pollen a month, growing every month you stay", "A returning subscriber sees their own step")
	_check(Benefits.content(true, false).panels.map(func(panel: Dictionary) -> String: return panel.name) == ["FullJourneyBoost"], "No Pollen a month while the grant is off")
	_check(Benefits.content(false, true).panels.is_empty(), "No Pollen panels at all while Pollen is off")

func _setup(subscribed: bool, grant_on: bool) -> Dictionary:
	var api := Api.new()
	root.add_child(api)
	var wallet := PollenWallet.new(_path("client-wallet"))
	var grant := PollenGrant.new(_path("client-grant"))
	var fake := Fake.new()
	fake.tree = self
	var scope := func() -> Dictionary: return {"server": api.base_url, "owner": ME}
	var client: RefCounted = Client.new(api, scope, fake.call_it, wallet)
	client.grant = grant
	client.wardrobe = null
	var who := {"subscribed": subscribed}
	client.subscribed = func() -> bool: return bool(who.subscribed)
	wallet.set_enabled(api.base_url, ME, true)
	wallet.note_wallet(api.base_url, ME, {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0})
	grant.set_enabled(api.base_url, ME, grant_on)
	return {"api": api, "wallet": wallet, "grant": grant, "fake": fake, "client": client, "who": who}

func _settle(client: RefCounted) -> void:
	for i in range(40):
		if not client.sending(): return
		await process_frame

func _client_reads() -> void:
	var t := _setup(true, true)
	t.fake.replies = [{"ok": false, "code": "connection_interrupted"}]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1, "An offline read counts for nothing")
	t.fake.sent.clear()
	t.fake.replies = [{"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}]
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1 and t.fake.sent[0].path == "/v1/pollen", "A Full Journey phone reads the wallet for the grant, though it has one")
	_check(t.grant.pending(t.api.base_url, ME).amount == 4500 and t.wallet.wallet(t.api.base_url, ME).balance == 4500, "and keeps the grant and the balance")
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1, "Not again on the next flush: at most every few hours")
	var free := _setup(false, true)
	free.client.flush()
	await _settle(free.client)
	_check(free.fake.sent.is_empty(), "A free player's phone never reads for the grant")
	var off := _setup(true, false)
	off.client.flush()
	await _settle(off.client)
	_check(off.fake.sent.is_empty(), "Nor while the grant is off")
	for each: Dictionary in [t, free, off]: each.api.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
