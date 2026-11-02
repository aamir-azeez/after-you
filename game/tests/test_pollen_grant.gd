extends SceneTree
## The Full Journey monthly Pollen on this phone (services/pollen_grant.gd,
## presentation/pollen_grant_card.gd, presentation/full_journey_benefits.gd and
## the grant read in services/pollen_client.gd), through a fake transport:
## - the wallet answer's grant part is kept only in the contract's shape;
## - "Your monthly Pollen arrived" shows once per instalment, only while the
##   grant is on and only for a recent one, and says the month and what next
##   month pays (its board, Home and first taps: test_full_journey_board.gd);
## - months paid together after a long absence (2, 3, across the top step)
##   share one card naming how many and their Pollen added up, and anything
##   that cannot be told for sure shows the newest month alone;
## - replies that land out of order never bring back an older instalment, nor
##   its card, and a file from before shown_at keeps what it showed;
## - the Wardrobe's wallet read keeps the grant part too;
## - the Full Journey card lists the chapters first, then the room boost, then
##   the monthly Pollen, and the Pollen panels only while the server pays them;
## - a phone with Full Journey reads the wallet for the grant once a launch and
##   then at most every few hours, saying so in its Full Journey header; a free
##   player's phone never does;
## - a Full Journey purchase or restore sends one wallet read saying "bought" at
##   once, even right after a grant read, and only while the grant is on.
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenGrant = preload("res://services/pollen_grant.gd")
const Client = preload("res://services/pollen_client.gd")
const GrantCard = preload("res://presentation/pollen_grant_card.gd")
const Benefits = preload("res://presentation/full_journey_benefits.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const AtomicFile = preload("res://services/atomic_file.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")

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
	func call_it(method: int, path: String, body: Dictionary, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
		sent.append({"method": method, "path": path, "body": body.duplicate(true), "headers": headers})
		await tree.process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "code": "connection_interrupted"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_checked()
	_cards()
	_catch_up()
	_order()
	await _wardrobe_read()
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
	_check(card == {"key": "grant:1790000000000:1", "amount": 4500, "next": 4750, "top": 12000, "months": 1, "since": 0}, "A new instalment has its card: " + str(card))
	store.mark_shown(SERVER, ME, card.key)
	_check(store.pending(SERVER, ME).is_empty(), "Once shown, it never shows again")
	var reloaded := PollenGrant.new(store.path)
	_check(reloaded.pending(SERVER, ME).is_empty() and reloaded.ladder(SERVER, ME).next == 4750, "That survives a restart, with the ladder")
	reloaded.note_view(SERVER, ME, _answer(2, 5000, "grant:1790000000000:2", 4750))
	_check(reloaded.pending(SERVER, ME).amount == 4750, "Next month's instalment has its own card")
	var fresh := PollenGrant.new(_path("cards-old"))
	fresh.set_enabled(SERVER, ME, true)
	fresh.note_view(SERVER, ME, _answer(3, 5250, "grant:1790000000000:3", 5000, _now() - 40 * DAY_MS))
	_check(fresh.pending(SERVER, ME).is_empty(), "An old instalment (a new install, a long absence) is not news")
	_check(not reloaded.note_view(SERVER, ME, {"schema_version": 1.0, "balance": 0.0}), "A wallet answer with no grant part changes nothing")

## Months paid together share one card: how many, and their Pollen added up.
func _catch_up() -> void:
	var store := PollenGrant.new(_path("catch-up"))
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, _answer(1, 4750, "grant:1790000000000:1", 4500, _now() - 3 * DAY_MS))
	var first: Dictionary = store.pending(SERVER, ME)
	_check(GrantCard.summary(first) == {"count": 1, "total": 4500}, "The first card names its month alone: " + str(GrantCard.summary(first)))
	store.mark_shown(SERVER, ME, first.key)
	# Two months away: the next read pays months 2 and 3.
	store.note_view(SERVER, ME, _answer(3, 5250, "grant:1790000000000:3", 5000, _now() - 2 * DAY_MS))
	var two: Dictionary = store.pending(SERVER, ME)
	_check(two.since == 2 and GrantCard.summary(two) == {"count": 2, "total": 9750}, "Two months at once: both, added up: " + str(two) + " " + str(GrantCard.summary(two)))
	_check(GrantCard.month_line(two) == "From Full Journey, 2 months of your ladder.\nNext month: 5,250.", "and the line says so: " + GrantCard.month_line(two))
	store.mark_shown(SERVER, ME, two.key)
	var reloaded := PollenGrant.new(store.path)
	_check(reloaded.pending(SERVER, ME).is_empty(), "Shown, it stays shown after a restart")
	# Three months away.
	var before: int = reloaded.revision
	reloaded.note_view(SERVER, ME, _answer(6, 6000, "grant:1790000000000:6", 5750, _now() - DAY_MS))
	_check(reloaded.revision == before + 1, "A new instalment moves the revision, so Home looks again")
	reloaded.note_view(SERVER, ME, _answer(6, 6000, "grant:1790000000000:6", 5750, _now() - DAY_MS))
	_check(reloaded.revision == before + 1, "The same instalment read again does not")
	var three: Dictionary = reloaded.pending(SERVER, ME)
	_check(three.since == 3 and GrantCard.summary(three) == {"count": 3, "total": 16500}, "Three months at once: " + str(GrantCard.summary(three)))
	_check(GrantCard.amount_text(int(GrantCard.summary(three).total)) == "+16,500", "The big figure is their sum")
	# A card not shown yet (the phone never reached Home) and another month on top: one card for all four.
	reloaded.note_view(SERVER, ME, _answer(7, 6250, "grant:1790000000000:7", 6000, _now() - 12 * 3600000))
	_check(GrantCard.summary(reloaded.pending(SERVER, ME)) == {"count": 4, "total": 22500}, "Months kept while no card showed add up too")
	# Across the top step: months 30 and 31 pay 11,750 and 12,000.
	_check(GrantCard.summary({"key": "grant:1790000000000:31", "amount": 12000, "next": 12000, "top": 12000, "months": 31, "since": 2}) == {"count": 2, "total": 23750}, "Each month at its own step, up to the top")
	var single := {"count": 1, "total": 4500}
	for unsure: Dictionary in [
			{"key": "grant:1790000000000:5", "amount": 4500, "next": 5750, "top": 12000, "months": 5, "since": 2},
			{"key": "grant:1790000000000:5", "amount": 4500, "next": 4750, "top": 12000, "months": 1, "since": 0},
			{"key": "grant:lifetime", "amount": 4500, "next": 5250, "top": 12000, "months": 3, "since": 2},
			{"key": "grant:1790000000000:49", "amount": 4500, "next": 12000, "top": 12000, "months": 60, "since": 49}]:
		_check(GrantCard.summary(unsure) == single, "What cannot be told for sure shows the newest month alone: " + str(unsure))
	var unknown := PollenGrant.new(_path("catch-up-new"))
	unknown.set_enabled(SERVER, ME, true)
	unknown.note_view(SERVER, ME, _answer(3, 5250, "grant:1790000000000:3", 5000))
	_check(GrantCard.summary(unknown.pending(SERVER, ME)) == {"count": 1, "total": 5000}, "A phone with no card to count from (a new install) names the newest month alone")

## Replies land out of order: an older instalment never comes back, nor its card.
func _order() -> void:
	var store := PollenGrant.new(_path("order"))
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, _answer(2, 5000, "grant:1790000000000:2", 4750, _now() - DAY_MS))
	store.note_view(SERVER, ME, _answer(1, 4750, "grant:1790000000000:1", 4500, _now() - 2 * DAY_MS))
	_check(store.ladder(SERVER, ME).months == 2 and store.pending(SERVER, ME).key == "grant:1790000000000:2", "A late reply with an older instalment changes nothing")
	store.mark_shown(SERVER, ME, "grant:1790000000000:2")
	store.note_view(SERVER, ME, _answer(1, 4750, "grant:1790000000000:1", 4500, _now() - 2 * DAY_MS))
	_check(store.pending(SERVER, ME).is_empty(), "nor shows its card after a newer one")
	var scope := PollenGrant.scope_key(SERVER, ME)
	var older := _path("order-file")
	var ladder := {"months": 1, "next": 4750, "top": 12000, "latest": {"key": "grant:1790000000000:1", "amount": 4500, "at": _now() - 2 * DAY_MS}}
	AtomicFile.write_text(older, JSON.stringify({"schema_version": 1, "scopes": {scope: {"enabled": true, "ladder": ladder, "shown": "grant:1790000000000:2", "shown_at": _now() - DAY_MS, "shown_months": 2}}}))
	_check(PollenGrant.new(older).pending(SERVER, ME).is_empty(), "A kept instalment older than the one shown never shows")
	# A file from before shown_at: what it showed stays shown, and counts for the next card.
	var legacy := _path("order-legacy")
	AtomicFile.write_text(legacy, JSON.stringify({"schema_version": 1, "scopes": {scope: {"enabled": true, "ladder": ladder, "shown": "grant:1790000000000:1"}}}))
	var loaded := PollenGrant.new(legacy)
	_check(loaded.pending(SERVER, ME).is_empty(), "An older file's shown card does not show again")
	loaded.note_view(SERVER, ME, _answer(3, 5250, "grant:1790000000000:3", 5000, _now() - DAY_MS))
	_check(int(loaded.pending(SERVER, ME).get("since", 0)) == 2, "and the next card counts from it")
	var unseen := _path("order-unseen")
	AtomicFile.write_text(unseen, JSON.stringify({"schema_version": 1, "scopes": {scope: {"enabled": true, "ladder": ladder, "shown": ""}}}))
	_check(PollenGrant.new(unseen).pending(SERVER, ME).get("key") == "grant:1790000000000:1", "An instalment an earlier build kept and never showed shows once")
	var off := PollenGrant.new(_path("order-enable"))
	var turned: int = off.revision
	off.set_enabled(SERVER, ME, true)
	_check(off.revision == turned + 1, "The grant turning on moves the revision too")

## The Wardrobe's own wallet read can be the one that pays: it keeps the grant part.
func _wardrobe_read() -> void:
	var wardrobe := Wardrobe.new(_path("wardrobe-store"))
	var wallet := PollenWallet.new(_path("wardrobe-wallet"))
	var grant := PollenGrant.new(_path("wardrobe-grant"))
	wardrobe.set_enabled(SERVER, ME, true, false)
	wallet.set_enabled(SERVER, ME, true)
	grant.set_enabled(SERVER, ME, true)
	var data := _answer(1, 4750, "grant:1790000000000:1", 4500)
	data["wardrobe"] = {"items": [], "packs": [], "look": {}, "look_revision": 1.0, "offered": ["daisy", "seashell"], "offered_packs": [], "sets": {}, "unlocked": []}
	var replies := [{"ok": true, "status": 200, "data": data}]
	var transport := func(_method: int, _path_: String, _body: Dictionary) -> Dictionary:
		await process_frame
		return replies.pop_front() if not replies.is_empty() else {"ok": false, "code": "connection_interrupted"}
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, transport, wardrobe, wallet)
	client.grant = grant
	await client.refresh()
	_check(grant.pending(SERVER, ME).get("amount") == 4500, "The Wardrobe's read keeps the monthly Pollen it paid")
	var broken := _answer(2, 5000, "grant:1790000000000:2", 4750)
	broken["wardrobe"] = "not a wardrobe"
	replies.append({"ok": true, "status": 200, "data": broken})
	await client.refresh()
	_check(grant.pending(SERVER, ME).get("amount") == 4750, "even when its wardrobe part could not be kept")

func _card_view() -> void:
	_check(GrantCard.amount_text(4750) == "+4,750", "The big amount")
	_check(GrantCard.month_line({"key": "grant:1790000000000:2", "amount": 4750, "next": 5000, "top": 12000, "months": 2}) == "From Full Journey, month 2 of your ladder.\nNext month: 5,000.", "The month line")
	_check(GrantCard.month_line({"key": "grant:1790000000000:1", "amount": 4500, "next": 4750, "top": 12000, "months": 0}) == PlayerCopy.POLLEN_GRANT_NEXT % "4,750", "A month count below the instalment (a refund) names no month")
	_check(GrantCard.month_line({"key": "grant:lifetime", "amount": 4500, "next": 12000, "top": 12000, "months": 31}) == PlayerCopy.POLLEN_GRANT_LIFETIME, "The Lifetime thank you names no month")
	for line: String in [PlayerCopy.POLLEN_GRANT_TITLE, PlayerCopy.POLLEN_GRANT_MONTH, PlayerCopy.POLLEN_GRANT_MONTHS, PlayerCopy.POLLEN_GRANT_LIFETIME, PlayerCopy.POLLEN_GRANT_NEXT, PlayerCopy.POLLEN_GRANT_WARDROBE, PlayerCopy.POLLEN_GRANT_DONE,
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
	_check(t.fake.sent[0].headers == PackedStringArray(["X-AfterYou-Full-Journey: 1"]), "and says it has Full Journey: " + str(t.fake.sent[0].headers))
	_check(t.grant.pending(t.api.base_url, ME).amount == 4500 and t.wallet.wallet(t.api.base_url, ME).balance == 4500, "and keeps the grant and the balance")
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 1, "Not again on the next flush: at most every few hours")
	# A purchase or restore reads at once, saying so, though the grant read just went.
	t.fake.replies = [{"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}, {"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}]
	t.client.note_full_journey_bought()
	await _settle(t.client)
	_check(t.fake.sent.size() == 2 and t.fake.sent[1].headers == PackedStringArray(["X-AfterYou-Full-Journey: bought"]), "A purchase reads the wallet at once, saying bought: " + str(t.fake.sent.back().get("headers")))
	t.client.flush()
	await _settle(t.client)
	_check(t.fake.sent.size() == 2, "Once: the next flush reads nothing more")
	var free := _setup(false, true)
	free.client.flush()
	await _settle(free.client)
	_check(free.fake.sent.is_empty(), "A free player's phone never reads for the grant")
	# A purchase whose read gets no answer goes again on the next flush, and only once answered stops.
	free.fake.replies = [{"ok": false, "code": "connection_interrupted"}, {"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}]
	free.client.note_full_journey_bought()
	await _settle(free.client)
	free.client.flush()
	await _settle(free.client)
	free.client.flush()
	await _settle(free.client)
	_check(free.fake.sent.size() == 2 and free.fake.sent.all(func(each: Dictionary) -> bool: return each.headers == PackedStringArray(["X-AfterYou-Full-Journey: bought"])), "A purchase read that failed goes again, then stops: " + str(free.fake.sent.size()))
	var off := _setup(true, false)
	off.client.flush()
	await _settle(off.client)
	# While a purchase is under way the store already says Full Journey (and the app resumes from its sheet):
	# the plain grant read waits, so the purchase's own "bought" read is the one the server sees.
	var buying := _setup(true, true)
	var store := {"busy": true}
	buying.client.purchasing = func() -> bool: return bool(store.busy)
	buying.client.flush()
	await _settle(buying.client)
	_check(buying.fake.sent.is_empty(), "No plain grant read while a purchase is under way")
	store.busy = false
	buying.fake.replies = [{"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}]
	buying.client.note_full_journey_bought()
	await _settle(buying.client)
	_check(buying.fake.sent.size() == 1 and buying.fake.sent[0].headers == PackedStringArray(["X-AfterYou-Full-Journey: bought"]), "then the purchase's read says bought, and it alone goes: " + str(buying.fake.sent.size()))
	buying.api.queue_free()
	# The store may list a new purchase a little late: an answer with nothing paid tries again, not at once
	# but after the server's ten minutes, and gives up after three answered tries.
	var late := _setup(false, true)
	var empty := {"ok": true, "data": {"schema_version": 1.0, "balance": 0.0, "earned": 0.0, "bank": 12.0}}
	late.fake.replies = [empty, empty, empty, empty]
	late.client.note_full_journey_bought()
	await _settle(late.client)
	late.client.flush()
	await _settle(late.client)
	_check(late.fake.sent.size() == 1, "Nothing paid yet: no second try at once")
	for n in range(3):
		for key: String in late.client._bought.keys(): late.client._bought[key].at = 0
		late.client.flush()
		await _settle(late.client)
	_check(late.fake.sent.size() == 3, "Three answered tries in all, then it stops: " + str(late.fake.sent.size()))
	var paid := _setup(false, true)
	paid.fake.replies = [empty, {"ok": true, "data": _answer(1, 4750, "grant:1790000000000:1", 4500)}]
	paid.client.note_full_journey_bought()
	await _settle(paid.client)
	for key: String in paid.client._bought.keys(): paid.client._bought[key].at = 0
	paid.client.flush()
	await _settle(paid.client)
	_check(paid.fake.sent.size() == 2 and paid.grant.pending(paid.api.base_url, ME).amount == 4500 and paid.client._bought.is_empty(), "The second try pays and ends the purchase's reads")
	for each: Dictionary in [late, paid]: each.api.queue_free()
	off.client.note_full_journey_bought()
	await _settle(off.client)
	_check(off.fake.sent.is_empty(), "Nor while the grant is off, even after a purchase")
	for each: Dictionary in [t, free, off]: each.api.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
