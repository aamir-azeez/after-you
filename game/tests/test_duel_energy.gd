extends SceneTree
## Duel energy (ENERGY-PLAN.md, boards 10) through fake transports and synthetic ids only:
## - the meter's arithmetic on the server's clock (services/duel_energy.gd): the
##   count and "Next in" minutes, the phone's clock set apart from the server's,
##   a clock turned back, Full Journey's 7, replies out of order, an empty
##   refusal, and when the wallet is read for it;
## - every part through services/wallet_reply.gd: the wallet read, the refill
##   receipt and the duel start and join replies (services/duels_client.gd), the
##   capability (services/relay_online_session.gd) and the refill spend
##   (services/wardrobe_client.gd refill_energy);
## - the lobby's meter and the cost chip on every start and join button, and
##   none of it while energy is off;
## - the out-of-energy card (Wait always, Refill only with Fruits and below the
##   max, held offline), the refusals (energy_empty, partner_energy_empty) and
##   the refill confirm (presentation/fruit_spend_flow.gd refill_energy);
## - the Full Journey perk line, from the server's two tops only;
## - offline: Start a duel, Accept, Send challenge and every Race grey, and the
##   duels flow sends nothing.
const DuelEnergy = preload("res://services/duel_energy.gd")
const WalletReply = preload("res://services/wallet_reply.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Connectivity = preload("res://services/connectivity.gd")
const Registry = preload("res://services/chapter_registry.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const UiTokens = preload("res://presentation/ui_tokens.gd")
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const RacePicker = preload("res://presentation/duels/duel_race_picker.gd")
const ListPage = preload("res://presentation/duels/public_list_page.gd")
const PublicSheets = preload("res://presentation/duels/public_sheets.gd")
const PublicClient = preload("res://services/public_duels_client.gd")
const EnergyMeter = preload("res://presentation/duels/energy_meter.gd")
const EnergyFlow = preload("res://presentation/duels/duel_energy_flow.gd")
const EnergyChip = preload("res://presentation/kit/energy_chip.gd")
const SproutMark = preload("res://presentation/kit/sprout_mark.gd")
const SpendFlow = preload("res://presentation/fruit_spend_flow.gd")
const Benefits = preload("res://presentation/full_journey_benefits.gd")
const BenefitPanel = preload("res://presentation/kit/benefit_panel.gd")
const InGameModal = preload("res://presentation/in_game_modal.gd")
const DuelsFlow = preload("res://presentation/duels/duels_flow.gd")

# Synthetic ids only.
const SERVER := "https://energy.example.test"
const ME := "eeeeeeeeeeeeeeeeeeeeee"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const DUEL := "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0"
const BOARD := "first-steps@1"
const STEP := 600000
## Jan 15, 2027, noon UTC: the server's clock in every part.
const T0 := 1800014400000
## Three of five, the next in six minutes: full in 16.
const FULL_AT := T0 + 960000

var checks := 0
var failures := 0
var _paths: Array[String] = []

class Clock extends RefCounted:
	var ms := 0
	func now() -> int: return ms

class Online extends RefCounted:
	var on := true
	signal changed(online: bool)
	func online() -> bool: return on
	func check_now() -> void: pass

## The spend route: answers each POST with `answer`.
class Server extends RefCounted:
	var answer: Dictionary = {}
	var sent: Array = []
	func call_it(method: int, path: String, body: Dictionary) -> Dictionary:
		await Engine.get_main_loop().process_frame
		sent.append([method, path, body.duplicate(true)])
		return answer.duplicate(true)

class FakeApi extends Node:
	var base_url := SERVER
	var player_id := ME
	var replies: Dictionary = {}
	var requests: Array = []
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		requests.append([method, path, body])
		await Engine.get_main_loop().process_frame
		return replies.get(path, {"ok": false, "status": 0, "code": "connection_interrupted"}).duplicate(true)

class FakePollen extends RefCounted:
	var flushes := 0
	func flush() -> void: flushes += 1

class FakeSpends extends Node:
	var shows := true
	var asked: Array = []
	func visible() -> bool: return shows
	func refill_energy(parent: Control, opener: Control = null) -> Control:
		asked.append(opener)
		return InGameModal.open(parent, "FakeRefillCard", "Refill")

class FakeMain extends Node:
	var api: Node
	var pollen_client: RefCounted = FakePollen.new()
	var fruit_spend_flow: Node
	var said: Array = []
	func _toast(text: String) -> void: said.append(text)

class FakeFlow extends Node:
	var host: Node

class Host extends Node:
	var said: Array = []
	var api: Node = null
	func _toast(text: String) -> void: said.append(text)

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _path(name: String) -> String:
	var path := "user://test_duel_energy_%s.json" % name
	_paths.append(path)
	return path

func _frames(count: int) -> void:
	for index in range(count): await process_frame

static func part(energy: int, top: int = 5, full_at: int = FULL_AT, now: int = T0) -> Dictionary:
	return {"schema_version": 1.0, "energy": float(energy), "max": float(top), "full_at": float(full_at), "step_ms": float(STEP), "now": float(now), "refill_fruits": 10.0,
		"base_max": 5.0, "full_journey_max": 7.0}

## A store for the test player, energy on, its clock `clock`, read once with `kept` unless it is {}.
func _store(clock: Clock, kept: Dictionary = {}) -> RefCounted:
	var store: RefCounted = DuelEnergy.new()
	store.clock = clock.now
	store.set_enabled(SERVER, ME, true)
	if not kept.is_empty(): WalletReply.note(SERVER, ME, {"energy": kept}, null, null, null, null, store)
	return store

func _run() -> void:
	var online := Online.new()
	Connectivity.use_shared(online)
	PollenSurfaces.set_shared_for_tests(true, true)
	_math()
	_reads()
	await _replies()
	await _refill_spend()
	await _lobby()
	await _pages()
	await _flow(online)
	await _refill_card(online)
	_full_journey()
	await _offline(online)
	DuelEnergy.use_shared(null)
	Connectivity.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	for path: String in _paths:
		for candidate: String in [path, path + ".tmp", path + ".bak"]:
			if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	print("AFTER YOU DUEL ENERGY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# --- The meter's arithmetic ------------------------------------------------

func _math() -> void:
	var clock := Clock.new()
	clock.ms = T0
	var store := _store(clock, part(3))
	var now: Dictionary = store.meter(SERVER, ME)
	_check(now.energy == 3 and now.max == 5 and DuelEnergy.minutes(now.next_ms) == 6, "3 of 5, the next in 6 min: %s" % [now])
	_check(PlayerCopy.ENERGY_METER % [now.energy, now.max] == "Energy 3 of 5" and PlayerCopy.ENERGY_NEXT % DuelEnergy.minutes(now.next_ms) == "Next in 6 min", "The meter's words as the board draws them")
	# The phone's clock an hour ahead of the server's: the same meter, from the server's own now.
	var ahead := Clock.new()
	ahead.ms = T0 + 3600000
	var skewed := _store(ahead, part(3))
	_check(skewed.meter(SERVER, ME) == now, "A phone clock an hour off reads the same meter: %s" % [skewed.meter(SERVER, ME)])
	ahead.ms += 360000
	var later: Dictionary = skewed.meter(SERVER, ME)
	_check(later.energy == 4 and DuelEnergy.minutes(later.next_ms) == 10, "Six minutes on, one more came and the next is 10 min away: %s" % [later])
	ahead.ms += 59000
	_check(DuelEnergy.minutes(skewed.meter(SERVER, ME).next_ms) == 10, "No seconds: the line stays at whole minutes")
	ahead.ms = T0 + 3600000 + 960000
	var full: Dictionary = skewed.meter(SERVER, ME)
	_check(full.energy == 5 and full.next_ms == 0 and DuelEnergy.next_change_ms(full.next_ms) == -1, "At full nothing counts on and nothing waits: %s" % [full])
	_check(DuelEnergy.minutes(1) == 1 and DuelEnergy.minutes(60000) == 1 and DuelEnergy.minutes(60001) == 2, "Minutes round up and are never 0")
	_check(DuelEnergy.next_change_ms(360000) == 60000 and DuelEnergy.next_change_ms(61000) == 1000, "The next redraw waits for the minute to change, at most a minute")
	# The clock turned back after the part came: never below what the server said.
	ahead.ms = T0
	var back: Dictionary = skewed.meter(SERVER, ME)
	_check(back.energy == 3 and back.next_ms > 0 and back.next_ms <= STEP, "A clock turned back keeps the server's count: %s" % [back])
	# Full Journey's 7.
	var journey := _store(clock, part(7, 7, T0 - 1))
	_check(journey.meter(SERVER, ME).energy == 7 and journey.meter(SERVER, ME).max == 7, "Full Journey holds 7")
	var five_of_seven := _store(clock, part(5, 7, T0 + 2 * STEP))
	_check(five_of_seven.meter(SERVER, ME).energy == 5 and DuelEnergy.minutes(five_of_seven.meter(SERVER, ME).next_ms) == 10, "5 of 7 with two to come")
	# Out of order: the part with the newest server time stands.
	var order := _store(clock, part(2, 5, T0 + 3 * STEP, T0 + 1000))
	_check(not order.note_view(SERVER, ME, {"energy": part(4, 5, T0 + STEP, T0)}), "A read sent before a start, answered after it, changes nothing")
	_check(order.meter(SERVER, ME).energy == 2, "The start's meter stands")
	# An empty refusal: 0 with no minutes until the read, which brings them back.
	order.note_empty(SERVER, ME)
	var empty: Dictionary = order.meter(SERVER, ME)
	_check(empty.energy == 0 and empty.next_ms == -1 and order.needs_read(SERVER, ME), "energy_empty: 0, no minutes, and a read is wanted")
	_check(not order.empty_now(SERVER, ME), "While the minutes are unknown a tap still goes to the server, so a failed read never stops every start")
	order.note_view(SERVER, ME, {"energy": part(0, 5, T0 + 5 * STEP + 1000, T0 + 2000)})
	_check(order.meter(SERVER, ME).energy == 0 and DuelEnergy.minutes(order.meter(SERVER, ME).next_ms) == 10 and not order.needs_read(SERVER, ME) and order.empty_now(SERVER, ME), "The read brings the minutes back, and an empty meter opens the card at once")
	_check(not order.note_view(SERVER, ME, {"energy": part(1, 5, T0 + 4 * STEP, T0 + 2000)}) and order.meter(SERVER, ME).energy == 0, "Two parts from one server moment: the later full_at (the spend) stands")
	# Parts off the contract are dropped.
	for bad: Dictionary in [part(6, 5), part(1).merged({"schema_version": 2.0}, true), part(1).merged({"step_ms": 0.0}, true), part(1).merged({"full_at": -1.0}, true), part(1).merged({"refill_fruits": "ten"}, true), {}]:
		_check(DuelEnergy.checked(bad).is_empty(), "A part off the contract is dropped: %s" % [bad])
	# Off: nothing shows, and what was kept goes.
	store.set_enabled(SERVER, ME, false)
	_check(store.meter(SERVER, ME).is_empty() and not store.enabled(SERVER, ME) and not store.needs_read(SERVER, ME), "Energy off: no meter and no read")
	_check(not store.refill_offered(SERVER, ME) and not store.empty_now(SERVER, ME), "Energy off: no refill and no empty card")

func _reads() -> void:
	var clock := Clock.new()
	clock.ms = T0
	var store := _store(clock)
	_check(store.needs_read(SERVER, ME) and store.meter(SERVER, ME).is_empty(), "Energy on with nothing kept: the wallet is read for it")
	WalletReply.note(SERVER, ME, {"energy": part(3)}, null, null, null, null, store)
	_check(not store.needs_read(SERVER, ME) and not store.ask_fresh(SERVER, ME), "A fresh meter wants no read when Duels opens")
	clock.ms += DuelEnergy.FRESH_MS
	_check(store.ask_fresh(SERVER, ME), "One older than its fresh time is read when Duels opens")
	var unkept := _store(clock)
	unkept.note_view(SERVER, ME, {"balance": 1.0})
	_check(not unkept.needs_read(SERVER, ME), "A read with no energy part asks no more this launch")
	var off: RefCounted = DuelEnergy.new()
	_check(not off.needs_read(SERVER, ME) and not off.ask_fresh(SERVER, ME), "Energy off never reads")
	_check(store.refill_offered(SERVER, ME) and not _store(clock, part(5, 5, T0 - 1)).refill_offered(SERVER, ME), "A refill is offered only below the max")

# --- Replies -----------------------------------------------------------------

func _view(status: String) -> Dictionary:
	var side := {"members": [ME, MAYA], "you": true, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none", "room_id": null, "invite_code": null, "hosting": false}
	return {"schema_version": 1, "duel_id": DUEL, "kind": "friend", "board": BOARD, "status": status, "steps": 4, "created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0,
		"ghost": null, "result": null, "eligible": true, "sides": [side, {"members": [FINN, null], "you": false, "steps": 0, "ticks": 0, "turn": null, "finished": false, "left": false, "check": "none"}]}

func _replies() -> void:
	var clock := Clock.new()
	clock.ms = T0
	var store := _store(clock, part(4))
	DuelEnergy.use_shared(store)
	# The refill receipt and the start replies feed the same store.
	WalletReply.note_spend(SERVER, ME, {"schema_version": 1.0, "energy": part(5, 5, T0 + 10, T0 + 10)}, null, null, null, store)
	_check(store.meter(SERVER, ME).energy == 5, "A refill receipt fills the kept meter")
	var api := FakeApi.new()
	root.add_child(api)
	var client: RefCounted = DuelsClient.new(api, ME, _path("duels"))
	api.replies["/v1/duels/challenge"] = {"ok": true, "status": 200, "data": {"schema_version": 1, "duel": _view("challenged"), "energy": part(4, 5, T0 + 20 + STEP, T0 + 20)}}
	var answer: Dictionary = await client.challenge(FINN, BOARD, DuelsClient.new_key())
	_check(answer.ok and store.meter(SERVER, ME).energy == 4, "A challenge's reply brings the meter after its spend: %s" % [store.meter(SERVER, ME)])
	api.replies["/v1/duels/ghost"] = {"ok": true, "status": 200, "data": {"schema_version": 1, "duel": _view("running"), "energy": part(3, 5, T0 + 30 + 2 * STEP, T0 + 30)}}
	answer = await client.race_ghost(BOARD, "developer", null, DuelsClient.new_key())
	_check(store.meter(SERVER, ME).energy == 3, "A ghost race's too")
	api.replies["/v1/duels/%s/%s/accept" % [BOARD, DUEL]] = {"ok": true, "status": 200, "data": {"schema_version": 1, "duel": _view("running"), "energy": part(2, 5, T0 + 40 + 3 * STEP, T0 + 40)}}
	answer = await client.act(BOARD, DUEL, "accept")
	_check(store.meter(SERVER, ME).energy == 2, "An accept's too")
	var public: RefCounted = PublicClient.new(api, client)
	api.replies["/v1/duels/public"] = {"ok": true, "status": 200, "data": {"schema_version": 1, "duel": _view("running"), "energy": part(1, 5, T0 + 50 + 4 * STEP, T0 + 50)}}
	answer = await public.post(BOARD, "alone", DuelsClient.new_key())
	_check(store.meter(SERVER, ME).energy == 1, "A public post's too, through the same answer")
	api.replies["/v1/duels/challenge"] = {"ok": false, "status": 409, "code": "energy_empty"}
	answer = await client.challenge(FINN, BOARD, DuelsClient.new_key())
	_check(not answer.ok and answer.code == "energy_empty" and store.meter(SERVER, ME).energy == 0 and store.needs_read(SERVER, ME), "A start refused as energy_empty reads 0 and asks for the wallet")
	api.replies["/v1/duels/challenge"] = {"ok": false, "status": 409, "code": "partner_energy_empty"}
	store.note_view(SERVER, ME, {"energy": part(3, 5, FULL_AT, T0 + 60)})
	answer = await client.challenge(FINN, BOARD, DuelsClient.new_key())
	_check(answer.code == "partner_energy_empty" and store.meter(SERVER, ME).energy == 3, "A partner's empty meter leaves this player's as it was")
	# The capability.
	var session: RefCounted = load("res://services/relay_online_session.gd").new(null, func() -> Dictionary: return {}, RefCounted.new())
	for item: Array in [[{"duels_version": 1.0, "duels_energy_version": 1.0}, true], [{"duels_version": 1.0}, false], [{"duels_energy_version": 1.0}, false], [{"duels_version": 1.0, "duels_energy_version": 2.0}, false]]:
		session.capabilities = item[0]
		_check(session.duels_energy_supported() == item[1], "Capability %s: energy %s" % [item[0], item[1]])
	api.queue_free()
	DuelEnergy.use_shared(null)

func _wardrobe_client(name: String, fruits: RefCounted, energy: RefCounted, server: Server) -> RefCounted:
	var wardrobe: RefCounted = Wardrobe.new(_path(name + "_wardrobe"))
	wardrobe.set_enabled(SERVER, ME, true, true)
	var wallet: RefCounted = PollenWallet.new(_path(name + "_wallet"))
	wallet.set_enabled(SERVER, ME, true)
	wallet.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": 24000.0, "earned": 24000.0, "bank": 15.0})
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, server.call_it, wardrobe, wallet, null, fruits, energy)
	client.connectivity = Online.new()
	return client

func _fruits(name: String, balance: int, on: bool = true) -> RefCounted:
	var store: RefCounted = FruitWallet.new(_path(name))
	store.set_enabled(SERVER, ME, on, true)
	store.note_view(SERVER, ME, {"fruits": {"schema_version": 1.0, "balance": float(balance), "earned": 120.0, "first_pack_gift": false, "first_pack_percent": 100.0, "achievements": []}})
	return store

func _refill_spend() -> void:
	var clock := Clock.new()
	clock.ms = T0
	var energy := _store(clock, part(0, 5, T0 + 5 * STEP - 1000))
	var fruits := _fruits("spend", 101)
	var server := Server.new()
	var client := _wardrobe_client("spend", fruits, energy, server)
	server.answer = {"ok": true, "status": 200, "data": {"schema_version": 1.0, "currency": "fruits", "balance": 24000.0, "fruit_balance": 91.0, "energy": part(5, 5, T0 + 100, T0 + 100)}}
	var answer: Dictionary = await client.refill_energy()
	_check(answer.ok and server.sent.size() == 1 and server.sent[0][2].kind == "energy" and server.sent[0][2].id == "energy" and int(server.sent[0][2].expected_cost) == 10, "Refill sends the energy spend at the price shown: %s" % [server.sent])
	_check(fruits.balance(SERVER, ME) == 91 and energy.meter(SERVER, ME).energy == 5, "The receipt is kept: 91 Fruits and a full meter")
	server.answer = {"ok": false, "status": 409, "code": "energy_full"}
	answer = await client.refill_energy()
	_check(answer.code == "energy_full" and server.sent.back()[0] == HTTPClient.METHOD_GET, "Refused at full: the meter is read again with the wallet")
	var off := _store(clock, part(1))
	off.set_enabled(SERVER, ME, false)
	server.sent.clear()
	answer = await _wardrobe_client("spend_off", fruits, off, server).refill_energy()
	_check(answer.code == "energy_disabled" and server.sent.is_empty(), "Energy off: nothing is sent")

# --- The lobby and the chips -------------------------------------------------

func _challenge_in() -> Dictionary:
	var view := _view("challenged")
	view.sides = [view.sides[1], view.sides[0]]
	view.mine = 1
	return DuelsClient.valid_view(view)

func _lobby() -> void:
	var clock := Clock.new()
	clock.ms = int(Time.get_unix_time_from_system() * 1000.0)
	var store: RefCounted = DuelEnergy.new()
	store.clock = clock.now
	store.set_enabled(SERVER, ME, true)
	store.note_view(SERVER, ME, {"energy": part(3, 5, clock.ms + 960000, clock.ms)})
	var lobby := {"party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_challenge_in()], "limits": {"friend": 10, "ghost": 3}}
	for on: bool in [true, false]:
		var screen := DuelsScreen.new()
		screen.me = ME
		screen.name_of = func(id: Variant) -> String: return "Maya" if id == MAYA else ""
		screen.energy_cost = on
		screen.energy_meter = EnergyMeter.pill(store, {"server": SERVER, "owner": ME}) if on else null
		root.add_child(screen)
		screen.show_lobby(lobby)
		await _frames(3)
		var start: Button = screen.root.find_child("DuelsStart", true, false)
		var accept: Button = screen.root.find_child("Accept", true, false)
		var race: Button = screen.root.find_child("DuelsRaceRecorded", true, false)
		var meter: Control = screen.root.find_child("EnergyMeter", true, false)
		var chips := [start, accept, race].filter(func(button: Button) -> bool: return button != null and button.find_child(EnergyChip.NAME, true, false) != null)
		if on:
			_check(chips.size() == 3, "Energy on: Start a duel, Accept and Race a recorded run wear the chip (%d)" % chips.size())
			_check(start.icon == null, "The chip takes the arrow's place on Start a duel")
			_check(meter != null and meter.visible, "The meter stands in the lobby header")
			var label: Label = meter.find_child("EnergyLabel", true, false)
			var next: Label = meter.find_child("EnergyNext", true, false)
			_check(label.text == "Energy 3 of 5" and next.visible and next.text == "Next in 6 min", "It reads Energy 3 of 5, Next in 6 min: %s / %s" % [label.text, next.text])
			_check(screen._subtitle.text == "", "The quiet line gives way to the meter")
			var timer: Timer = null
			for child: Node in meter.get_children(true):
				if child is Timer: timer = child
			_check(timer != null and not timer.is_stopped() and timer.wait_time <= 60.1 and timer.wait_time >= 1.0, "One timer, at most a minute away, no per second ticks: %s" % [timer.wait_time if timer != null else -1])
			store.note_view(SERVER, ME, {"energy": part(5, 5, clock.ms - 1, clock.ms + 1)})
			_check(label.text == "Energy 5 of 5" and not next.visible and timer.is_stopped(), "Full: no minutes line and no timer")
			var sprouts: Control = meter.find_child("SproutRow", true, false)
			_check(sprouts.lit == 5 and sprouts.count == 5, "Five sprouts, all lit")
			store.note_view(SERVER, ME, {"energy": part(3, 5, clock.ms + 960000, clock.ms + 2)})
			screen.visible = false
			await _frames(1)
			_check(timer.is_stopped(), "A hidden meter keeps no timer")
			screen.visible = true
			screen.note(DUEL, EnergyFlow.waiting_words("Maya"))
			screen.show_lobby(lobby)
			var said: Label = screen.root.find_child("ChallengeNote", true, false)
			_check(said != null and said.text == "Maya is waiting for energy", "The partner's wait stays under Accept through the lobby's redraw")
		else:
			_check(chips.is_empty() and meter == null, "Energy off: no chip and no meter")
			_check(screen._subtitle.text == PlayerCopy.DUELS_SUBTITLE, "and the quiet line stays")
		screen.close()
		await _frames(2)
	# The colours of the plan's table.
	_check(EnergyChip.FILL == Color("193d39") and EnergyChip.RING == Color("a6d9c4") and EnergyChip.NUMBER == Color("eceddb") and EnergyChip.RING_WIDTH == 1.5, "The chip's fill, ring and number are the plan's")
	_check(SproutMark.LEAF_LIGHT == Color("d9f59d") and SproutMark.LEAF_DEEP == Color("8fca5c") and SproutMark.STEM == Color("7fae55") and SproutMark.EMPTY == Color("5f8478") and SproutMark.EMPTY_WIDTH == 2.4, "The sprout's greens and outline are the plan's")
	_check(EnergyMeter.PILL_FILL == Color("18433e") and EnergyMeter.PILL_RING == Color("2f6359") and EnergyMeter.LINE == Color("afc6be") and EnergyMeter.LABEL == UiTokens.CREAM, "The meter pill's colours are the plan's")

func _has_chip(button: Node) -> bool:
	return button != null and button.find_child(EnergyChip.NAME, true, false) != null

func _pages() -> void:
	for on: bool in [true, false]:
		var label := "on" if on else "off"
		# Start a duel: Send challenge (and Post duel, the same button).
		var challenge := ChallengePage.new()
		challenge.energy_cost = on
		challenge.chapters = [Registry.FIRST_STEPS]
		root.add_child(challenge)
		await _frames(2)
		_check(_has_chip(challenge.root.find_child("DuelSend", true, false)) == on, "%s: Send challenge wears the chip only with energy on" % label)
		# Race a recorded run: Our run and the picker's Race.
		var ghosts := GhostPage.new()
		ghosts.energy_cost = on
		ghosts.chapters = [Registry.FIRST_STEPS]
		root.add_child(ghosts)
		ghosts.show_ghosts([{"board": Registry.FIRST_STEPS, "developer": 3000, "top": []}])
		await _frames(2)
		_check(_has_chip(ghosts.root.find_child("Race_developer", true, false)) == on, "%s: Race against our run wears the chip" % label)
		var picker: Control = RacePicker.open(ghosts, Registry.FIRST_STEPS, "Maya")
		picker.show_board([], {}, false, 3, 3000)
		await _frames(2)
		_check(_has_chip(picker.find_child("RacePickerOurRun", true, false)) == on, "%s: the picker's Race wears the chip" % label)
		ghosts.close()
		challenge.close()
		# Public duels: Join on each row, Post a duel, and Join and play.
		var list := ListPage.new()
		list.energy_cost = on
		list.boards = [[Registry.FIRST_STEPS, Registry.FIRST_STEPS]]
		list.known = func(_row: Dictionary) -> Dictionary: return {"chapter_open": true, "partner_on": true, "at_limit": false}
		root.add_child(list)
		await _frames(2)
		var row := PublicClient.valid_row({"duel_id": "b".repeat(32), "board": Registry.FIRST_STEPS, "posted_ms": 0, "open_until_ms": 7 * 86_400_000, "steps": 4, "mine": false,
			"sides": [{"steps": 1, "seats": [{"open": false, "label": "Kite"}, {"open": true, "label": null}]}, {"steps": 0, "seats": [{"open": true, "label": null}, {"open": true, "label": null}]}]})
		list.show_rows([row], -1)
		await _frames(2)
		_check(_has_chip(list.root.find_child("PublicJoin", true, false)) == on and _has_chip(list.root.find_child("PublicPost", true, false)) == on, "%s: Join and Post a duel wear the chip" % label)
		var card: Control = PublicSheets.join(list.root, row, 1, "alone", {"title": "First Steps", "partner": "", "energy_cost": on}, func() -> void: pass)
		_check(_has_chip(card.find_child("PublicJoinConfirm", true, false)) == on, "%s: Join and play wears the chip" % label)
		card.close(false)
		list.close()
		await _frames(2)

# --- The card, the refusals and the refill ---------------------------------

func _flow(online: Online) -> void:
	var clock := Clock.new()
	clock.ms = int(Time.get_unix_time_from_system() * 1000.0)
	var store: RefCounted = DuelEnergy.new()
	store.clock = clock.now
	store.set_enabled(SERVER, ME, true)
	var main := FakeMain.new()
	main.api = FakeApi.new()
	main.add_child(main.api)
	main.fruit_spend_flow = FakeSpends.new()
	main.add_child(main.fruit_spend_flow)
	root.add_child(main)
	var host := FakeFlow.new()
	host.host = main
	main.add_child(host)
	var energy: RefCounted = EnergyFlow.new(host, store)
	_check(energy.shown(), "The flow sees energy on for the signed-in player")
	energy.opened()
	_check(main.pollen_client.flushes == 1, "Duels opened with no meter kept: the wallet is read for it")
	store.note_view(SERVER, ME, {"energy": part(2, 5, clock.ms + 3 * STEP, clock.ms)})
	energy.opened()
	_check(main.pollen_client.flushes == 1, "A fresh meter is not read again")
	var page := ChallengePage.new()
	root.add_child(page)
	await _frames(2)
	var send: Button = page.root.find_child("DuelSend", true, false)
	_check(not energy.blocks(page, send), "With energy left a start goes to the server")
	# Empty: the card opens at once, nothing is sent.
	store.note_view(SERVER, ME, {"energy": part(0, 5, clock.ms + 5 * STEP - 1000, clock.ms + 1)})
	_check(energy.blocks(page, send), "With none left the tap opens the card instead")
	var out: Control = page.root.find_child("EnergyOut", true, false)
	_check(out != null and out.find_child("EnergyMeterCard", true, false) != null, "The out-of-energy card shows the meter")
	var line: RichTextLabel = out.find_child("EnergyNext", true, false) if out != null else null
	_check(line != null and line.text.contains("10 min") and line.text.begins_with("Your next energy comes in"), "and when the next one comes: %s" % [line.text if line != null else ""])
	_check(out.find_child("EnergyWait", true, false) != null and out.find_child("EnergyRefill", true, false) != null, "Wait always, and Refill while Fruits show")
	var refill: Button = out.find_child("EnergyRefill", true, false)
	_check(refill.find_child("WardrobeBuyContent", true, false) != null, "Refill reads Refill for, the Fruit and the price")
	refill.pressed.emit()
	await _frames(2)
	_check(main.fruit_spend_flow.asked.size() == 1 and page.root.find_child("FakeRefillCard", true, false) != null, "Refill opens the refill card over the page")
	page.close_sheet()
	# Without Fruits, only Wait.
	main.fruit_spend_flow.shows = false
	out = energy.out_card(page, send)
	await _frames(1)
	_check(out.find_child("EnergyRefill", true, false) == null and out.find_child("EnergyWait", true, false) != null, "Without Fruits: Wait alone")
	var wait: Button = out.find_child("EnergyWait", true, false)
	wait.pressed.emit()
	await _frames(2)
	_check(page.root.find_child("EnergyOut", true, false) == null, "Wait closes the card, and that is all")
	# Offline: Refill holds.
	main.fruit_spend_flow.shows = true
	online.on = false
	out = energy.out_card(page, send)
	await _frames(2)
	refill = out.find_child("EnergyRefill", true, false)
	_check(refill != null and refill.disabled, "Offline the Refill greys")
	online.on = true
	online.changed.emit(true)
	await _frames(1)
	_check(not refill.disabled, "and comes back with the connection")
	page.close_sheet()
	# The server's refusals.
	store.note_view(SERVER, ME, {"energy": part(3, 5, FULL_AT, clock.ms + 2)})
	var flushed: int = main.pollen_client.flushes
	_check(energy.refused(page, {"ok": false, "code": "energy_empty"}, send) and page.root.find_child("EnergyOut", true, false) != null and main.pollen_client.flushes == flushed + 1, "energy_empty opens the card and reads the meter")
	page.close_sheet()
	_check(energy.refused(page, {"ok": false, "code": "partner_energy_empty"}, send, "Maya"), "partner_energy_empty is energy's")
	var note: Label = page.root.find_child(EnergyFlow.NOTE, true, false)
	_check(note != null and note.text == "Maya is waiting for energy", "and says so where the button is: %s" % [note.text if note != null else ""])
	_check(EnergyFlow.waiting_words("") == "Your partner is waiting for energy", "A partner without a name: %s" % EnergyFlow.waiting_words(""))
	for code: String in ["energy_unavailable", "duel_limit_reached", ""]:
		_check(not energy.refused(page, {"ok": false, "code": code}, send), "%s stays the caller's usual line" % code)
	page.close()
	store.set_enabled(SERVER, ME, false)
	_check(not energy.shown() and energy.meter() == null and not energy.blocks(page, send), "Energy off: no meter, and a start is never stopped here")
	main.queue_free()
	await _frames(2)

func _refill_card(online: Online) -> void:
	var clock := Clock.new()
	clock.ms = T0
	var host := Host.new()
	root.add_child(host)
	var spend: Node = SpendFlow.new(host)
	host.add_child(spend)
	var parent := Control.new()
	parent.size = Vector2(1561, 720)
	host.add_child(parent)
	var server := Server.new()
	var energy := _store(clock, part(1, 5, T0 + 4 * STEP - 1000))
	var fruits := _fruits("card", 101)
	spend.client = _wardrobe_client("card", fruits, energy, server)
	var card: Control = spend.refill_energy(parent)
	_check(card != null and card.name == "WardrobeConfirm" and spend.sheet() == card, "Below the max with Fruits: the shared Fruit confirm card")
	_check(card.find_child("WardrobeConfirmPip", true, false) == null and card.find_child("EnergyRefillLine", true, false) != null, "No pip, the energy line on top")
	_check(card.title_label.text == "Refill energy?" and card.subtitle_label == null, "Refill energy?, with no line under it")
	var energy_line: Control = card.find_child("EnergyRefillLine", true, false)
	var from: Control = energy_line.find_child("EnergyNow", true, false)
	var to: Control = energy_line.find_child("EnergyFull", true, false)
	_check(from != null and to != null and from.lit == 1 and from.count == 5 and to.lit == 5, "From the meter now to full")
	var confirm: Button = card.find_child("EnergyRefillConfirm", true, false)
	_check(confirm != null and confirm.find_child("WardrobeBuyContent", true, false) != null, "A peach Refill for the Fruit and 10")
	server.answer = {"ok": true, "status": 200, "data": {"schema_version": 1.0, "currency": "fruits", "balance": 24000.0, "fruit_balance": 91.0, "energy": part(5, 5, T0 + 10, T0 + 10)}}
	confirm.pressed.emit()
	await _frames(6)
	_check(server.sent.size() == 1 and server.sent[0][2].kind == "energy" and energy.meter(SERVER, ME).energy == 5, "Refill fills the meter from the receipt")
	_check(spend.refill_energy(parent) == null, "At the max no refill is offered")
	# Short of 10 Fruits: the shared short card.
	energy.note_view(SERVER, ME, {"energy": part(1, 5, T0 + 4 * STEP, T0 + 20)})
	spend.client = _wardrobe_client("card_short", _fruits("card_short", 5), energy, server)
	card = spend.refill_energy(parent)
	_check(card != null and card.name == "WardrobeShort", "Short of the price, the shared short card")
	spend._close_sheet()
	# Fruits hidden: no refill.
	spend.client = _wardrobe_client("card_hidden", _fruits("card_hidden", 101, false), energy, server)
	_check(spend.refill_energy(parent) == null, "Without Fruits no refill")
	# Offline: nothing opens and the reason shows.
	spend.client = _wardrobe_client("card_off", _fruits("card_off", 101), energy, server)
	online.on = false
	_check(spend.refill_energy(parent) == null and host.said.back() == PlayerCopy.OFFLINE_NEEDS_CONNECTION, "Offline: nothing opens and the reason shows")
	online.on = true
	host.queue_free()
	await _frames(2)

# --- Full Journey ------------------------------------------------------------

func _full_journey() -> void:
	var clock := Clock.new()
	clock.ms = T0
	var store := _store(clock)
	_check(store.perk(SERVER, ME).is_empty(), "No perk line until a read brought the server's tops")
	var bare := part(3)
	bare.erase("full_journey_max")
	store.note_view(SERVER, ME, {"energy": bare})
	_check(store.perk(SERVER, ME).is_empty() and store.meter(SERVER, ME).energy == 3, "A part without both tops keeps the meter but names no perk")
	var odd := part(3, 5, FULL_AT, T0 + 1)
	odd.full_journey_max = 5.0
	store.note_view(SERVER, ME, {"energy": odd})
	_check(store.perk(SERVER, ME).is_empty(), "Tops that name no perk (the same top) show none")
	store.note_view(SERVER, ME, {"energy": part(3, 5, FULL_AT, T0 + 2)})
	var perk: Dictionary = store.perk(SERVER, ME)
	_check(perk == {"full_journey": 7, "plain": 5}, "The perk's numbers are the server's tops: %s" % [perk])
	var tops := part(3, 5, FULL_AT, T0 + 3)
	tops.base_max = 6.0
	tops.full_journey_max = 9.0
	store.note_view(SERVER, ME, {"energy": tops})
	_check(Benefits.content(true, true, {}, true, null, store.perk(SERVER, ME)).panels[0].title == "Duel energy: 9 instead of 6", "Whatever the server sends, the line says it")
	store.set_enabled(SERVER, ME, false)
	_check(store.perk(SERVER, ME).is_empty(), "Energy off: no perk")
	var with: Dictionary = Benefits.content(true, true, {}, true, null, {"full_journey": 7, "plain": 5})
	_check(with.panels.size() == 3 and with.panels[0].name == "FullJourneyEnergy", "The energy perk leads the panels, as the board places it: %s" % [with.panels.map(func(panel: Dictionary) -> String: return panel.name)])
	_check(with.panels[0].title == "Duel energy: 7 instead of 5" and with.panels[0].body == "" and with.panels[0].sprouts == 7, "Duel energy: 7 instead of 5, seven sprouts, no explainer")
	_check(Benefits.content(true, true).panels.all(func(panel: Dictionary) -> bool: return panel.name != "FullJourneyEnergy"), "Energy off: no perk line")
	_check(Benefits.content(true, true, {}, false, null, {"full_journey": 7, "plain": 5}).panels.is_empty(), "A build that names no Full Journey shows no perk either")
	var panel: Control = BenefitPanel.make(with.panels[0])
	var sprouts: Control = panel.find_child("PanelSprouts", true, false)
	_check(sprouts != null and sprouts.lit == 7 and sprouts.count == 7 and panel.find_child("EnergyIcon", true, false) != null, "The panel draws the sprout and seven lit sprouts")
	panel.free()

# --- Offline -----------------------------------------------------------------

func _held(button: Node) -> bool:
	return button is BaseButton and (button as BaseButton).disabled

func _offline(online: Online) -> void:
	online.on = false
	online.changed.emit(false)
	# The lobby: Start a duel and Accept.
	var screen := DuelsScreen.new()
	screen.me = ME
	screen.name_of = func(_id: Variant) -> String: return ""
	screen.energy_cost = true
	root.add_child(screen)
	screen.show_lobby({"party": {"partner": MAYA, "intact": true, "invites_in": [], "invite_out": null}, "duels": [_challenge_in()], "limits": {"friend": 10, "ghost": 3}})
	await _frames(2)
	_check(_held(screen.root.find_child("DuelsStart", true, false)) and _held(screen.root.find_child("Accept", true, false)), "Offline: Start a duel and Accept grey")
	# Send challenge, with a pair and a chapter picked.
	var challenge := ChallengePage.new()
	challenge.chapters = [Registry.FIRST_STEPS]
	challenge.friends = [{"id": FINN, "name": "Finn"}]
	root.add_child(challenge)
	await _frames(2)
	challenge._pick_friend(FINN)
	challenge._pick_chapter(Registry.FIRST_STEPS)
	var send: Button = challenge.root.find_child("DuelSend", true, false)
	_check(_held(send), "Offline: Send challenge greys though a pair and a chapter are picked")
	# Race against our run, and the picker's Race and Our run.
	var ghosts := GhostPage.new()
	ghosts.chapters = [Registry.FIRST_STEPS]
	root.add_child(ghosts)
	ghosts.show_ghosts([{"board": Registry.FIRST_STEPS, "developer": 3000, "top": []}])
	await _frames(2)
	_check(_held(ghosts.root.find_child("Race_developer", true, false)), "Offline: Race against our run greys")
	var picker: Control = RacePicker.open(ghosts, Registry.FIRST_STEPS, "Maya")
	picker.show_board([], {}, false, 3, 3000)
	await _frames(2)
	_check(_held(picker.find_child("RacePickerOurRun", true, false)), "Offline: the picker's Race greys")
	# The flow sends nothing and says why.
	var main := FakeMain.new()
	root.add_child(main)
	var flow: Node = DuelsFlow.new(main)
	main.add_child(flow)
	_check(flow._offline() and main.said.back() == PlayerCopy.OFFLINE_NEEDS_CONNECTION, "Offline: the duels flow refuses a start or join and says why")
	# Back online: each comes back, Send with the picks it had.
	online.on = true
	online.changed.emit(true)
	await _frames(1)
	_check(not _held(screen.root.find_child("DuelsStart", true, false)) and not _held(screen.root.find_child("Accept", true, false)) and not _held(send), "Online again: Start a duel, Accept and Send challenge come back")
	_check(not _held(ghosts.root.find_child("Race_developer", true, false)) and not _held(picker.find_child("RacePickerOurRun", true, false)), "and every Race")
	_check(not flow._offline(), "and the flow sends again")
	challenge._pick_friend("")
	_check(_held(send), "A Send with nothing picked stays grey for its own reason")
	screen.close()
	challenge.close()
	ghosts.close()
	main.queue_free()
	await _frames(2)
