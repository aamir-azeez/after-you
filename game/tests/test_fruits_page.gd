extends SceneTree
## The Fruits page and the Fruit surfaces in play (Fruits boards 6a, 6b, 7, 8):
## - the result card: a plum line per goal the credit paid, only while Fruits
##   show and only when it paid one; the Sunshine row ("Sunshine ×2") adds up
##   with the rest, and folds into Base while Fruits are hidden; a line's first
##   showing marks its goal shown, so no toast says it again;
## - the Sunshine card on the Pollen page: a dot per turn (the ones left golden),
##   "21 of 24 turns left", the price button only while a new one is offered,
##   and no card while Fruits are hidden; the history's "Sunshine ×2" tag;
## - Turn Fruits into Pollen: one step to start, steps of the server's size up to
##   the most the balance covers, the sums before confirming, the button's words,
##   and the button greyed offline; the spend flow's short card when the balance
##   misses a step or Sunshine's price, the confirm card when it covers it, and
##   each refusal read as a plain line;
## - the Fruits page: goals in the server's order (paid with their place and
##   "+10", the rest with their amount and steps, the keepsake goals greyed),
##   the first few until the link opens all ("All 15 goals, 340 Fruits in all"),
##   the newest Fruit lines named, the buttons that show (Get Fruits only while
##   packs sell), the page closed while Fruits are hidden, and every card inside
##   the screen at 1561x720 (the 1600x738 phone) and 1600x720 (800x360);
## - goal toasts: each once, one at a time, never while playing or in a room,
##   with View opening the Fruits page.
const FruitWallet = preload("res://services/fruit_wallet.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const WardrobeClient = preload("res://services/wardrobe_client.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const Connectivity = preload("res://services/connectivity.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Breakdown = preload("res://presentation/pollen_breakdown.gd")
const ResultLine = preload("res://presentation/pollen_result_line.gd")
const PlayPage = preload("res://presentation/pollen_play_page.gd")
const SunshineCard = preload("res://presentation/sunshine_card.gd")
const ConvertSheet = preload("res://presentation/fruit_convert_sheet.gd")
const SpendFlow = preload("res://presentation/fruit_spend_flow.gd")
const PageFlow = preload("res://presentation/fruits_page_flow.gd")
const WalletView = preload("res://presentation/fruit_wallet_view.gd")
const GoalsView = preload("res://presentation/fruit_goals_view.gd")
const Toasts = preload("res://presentation/fruit_unlock_toasts.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")

# Synthetic ids only.
const SERVER := "https://fruits-page.example.test"
const ME := "ffffffffffffffffffffff"
const ROOM := "rrrrrrrrrrrrrrrrrrrrrr"
const HASH := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
const SIZES := [Vector2i(1561, 720), Vector2i(1600, 720)]
const IDS := ["together_first", "together_five", "together_all", "hard_first", "hard_five", "hard_all", "duel_win_first", "duel_win_ten",
	"ghost_first", "ghost_five", "public_duel_first", "top_ten", "gold_leaf", "keepsake_first", "keepsake_all"]
const PAYS := [10, 10, 20, 10, 10, 40, 10, 10, 10, 10, 10, 50, 100, 10, 30]

var checks := 0
var failures := 0
var _paths: Array[String] = []

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

class FakeToast extends RefCounted:
	var lines: Array = []
	var up := false
	var action := Callable()
	func showing() -> bool: return up
	func post(line: String, _icon: Texture2D = null, _text: String = "", act: Callable = Callable()) -> void:
		lines.append(line)
		action = act
		up = true

class Host extends Node:
	var toast := FakeToast.new()
	var running := false
	var relay_child: Node3D = null
	var application_backgrounded := false
	var mode := "home"
	var overlay := Control.new()
	var title_font: Font = null
	var pollen_client: RefCounted
	var said: Array = []
	var api: Node = null
	func _init() -> void:
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(overlay)
	func _names_scope() -> Dictionary: return {"server": SERVER, "owner": ME}
	func _toast(text: String) -> void: said.append(text)
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children():
			overlay.remove_child(child)
			child.queue_free()

class History extends RefCounted:
	var answer: Dictionary = {}
	var reads := 0
	func history() -> Dictionary:
		reads += 1
		await Engine.get_main_loop().process_frame
		return answer.duplicate(true)

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _path(name: String) -> String:
	var path := "user://test_fruits_page_%s.json" % name
	_paths.append(path)
	return path

## The server's fifteen goals: the first and fourth paid on the Relay Isles, five
## chapters at 3 of 5, Hard five at 1 of 5, the keepsake goals not live.
static func _goals() -> Array:
	var rows := []
	for index in range(IDS.size()):
		var row := {"id": IDS[index], "fruits": float(PAYS[index]), "goal": 1.0, "progress": 0.0, "live": not IDS[index].begins_with("keepsake")}
		if IDS[index] in ["together_first", "hard_first", "duel_win_first"]:
			row.paid_at = 1800000000000.0
			row.progress = 1.0
			if IDS[index] != "duel_win_first": row.level_id = "relay-isles"
		if IDS[index] == "together_five": row.merge({"goal": 5.0, "progress": 3.0}, true)
		if IDS[index] == "hard_five": row.merge({"goal": 5.0, "progress": 1.0}, true)
		rows.append(row)
	return rows

static func _part(balance: int, left: int = 21, goals: Array = _goals()) -> Dictionary:
	return {"schema_version": 1.0, "balance": float(balance), "earned": 120.0, "sunshine": {"left": float(left), "turns": 24.0, "price": 20.0},
		"convert": {"pollen_per_fruit": 300.0, "step": 10.0}, "first_pack_gift": true, "first_pack_percent": 100.0, "achievements": goals}

## A Fruit store for the test player, Fruits on (packs too while `packs`), read once with `part`.
func _fruits(name: String, part: Dictionary, packs: bool = true) -> RefCounted:
	var store: RefCounted = FruitWallet.new(_path(name))
	store.set_enabled(SERVER, ME, true, packs)
	store.note_view(SERVER, ME, {"fruits": part})
	return store

func _client(name: String, fruits: RefCounted, server: Server, pollen: int = 24000) -> RefCounted:
	var wardrobe: RefCounted = Wardrobe.new(_path(name + "_wardrobe"))
	wardrobe.set_enabled(SERVER, ME, true, true)
	var wallet: RefCounted = PollenWallet.new(_path(name + "_wallet"))
	wallet.set_enabled(SERVER, ME, true)
	wallet.note_wallet(SERVER, ME, {"schema_version": 1.0, "balance": float(pollen), "earned": float(pollen), "bank": 15.0})
	var client: RefCounted = WardrobeClient.new(null, func() -> Dictionary: return {"server": SERVER, "owner": ME}, server.call_it, wardrobe, wallet, null, fruits)
	client.connectivity = Online.new()
	return client

func _run() -> void:
	PollenSurfaces.set_shared_for_tests(true, true)
	var online := Online.new()
	Connectivity.use_shared(online)
	_result_rows()
	await _result_line()
	await _sunshine_card()
	await _convert_sheet(online)
	await _spends(online)
	await _page()
	await _toasts()
	await _hud_pill()
	Connectivity.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	FruitWallet.use_shared(null)
	PollenWallet.use_shared(null)
	for path: String in _paths:
		for suffix: String in ["", ".tmp", ".backup", ".bad"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("AFTER YOU FRUITS PAGE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

static func _turn(extra: Dictionary = {}) -> Dictionary:
	var turn := {"kind": "bank", "base": 89.0, "bonuses": ["first_try"], "bonus_percents": [25.0], "bonus_percent": 25.0, "amount": 111.0,
		"bloom": 1.0, "bloom_extra": 0.0, "boost_percent": 10.0, "boost": 11.0, "total": 122.0, "boost_from": ["partner"]}
	turn.merge(extra, true)
	return turn

static func _receipt(turn: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var value := {"schema_version": 1.0, "earned": turn.get("total", 0.0), "balance": 1000.0, "turn": turn, "clears": []}
	value.merge(extra, true)
	return PollenWallet.checked_receipt(value)

static func _labels(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> String: return row.label + ("" if row.value.is_empty() else " = " + row.value))

static func _sum_to_total(rows: Array) -> bool:
	var sum := 0
	for row: Dictionary in rows:
		if row.kind == "total": return sum == int(str(row.value).replace(",", ""))
		if row.kind in ["base", "bonus", "boost", "duel", "sunshine"]: sum += int(str(row.value).replace(",", ""))
	return false

func _result_rows() -> void:
	# Sunshine paid the plain amount (111) again, in the total but not in the amount.
	var sunny := _receipt(_turn({"sunshine": 111.0, "total": 233.0}))
	var rows := Breakdown.rows(sunny)
	_check(_labels(rows) == ["Base = 89", "First try (25%) = 22", "Full Journey (10%) = 11", "Sunshine ×2 = 111", "This turn = 233"], "A Sunshine turn's rows: %s" % [_labels(rows)])
	_check(_sum_to_total(rows) and rows[3].plus and rows[3].grain, "The Sunshine row adds to This turn with its plus and grain")
	var hidden := Breakdown.rows(sunny, true, false)
	_check(_labels(hidden)[0] == "Base = 200" and not hidden.any(func(row: Dictionary) -> bool: return row.kind == "sunshine") and _sum_to_total(hidden), "Fruits hidden: Sunshine counts in Base and the rows still add up: %s" % [_labels(hidden)])
	var paid := _receipt(_turn(), {"fruits": {"balance": 111.0, "paid": [{"id": "hard_first", "amount": 10.0}]}})
	var with_fruit := Breakdown.rows(paid)
	_check(with_fruit.back().kind == "fruit" and with_fruit.back().label == "First Hard clear together" and with_fruit.back().value == "10 Fruits" and with_fruit.back().currency == "fruits", "A paid goal is a fruit row at the foot: %s" % [_labels(with_fruit)])
	_check(not Breakdown.rows(paid, true, false).any(func(row: Dictionary) -> bool: return row.kind == "fruit"), "No fruit row while Fruits are hidden")
	_check(not Breakdown.rows(_receipt(_turn())).any(func(row: Dictionary) -> bool: return row.kind in ["fruit", "sunshine"]), "A turn that paid no goal and used no Sunshine has neither row")
	_check(Breakdown.fruit_rows(_receipt(_turn(), {"fruits": {"balance": 5.0, "paid": [{"id": "not_a_goal", "amount": 10.0}]}})).is_empty(), "A goal this build cannot name shows no row")

func _result_line() -> void:
	var fruits := _fruits("line", _part(101))
	var wallet: RefCounted = PollenWallet.new(_path("line_wallet"))
	wallet.set_enabled(SERVER, ME, true)
	FruitWallet.use_shared(fruits)
	var receipt := {"schema_version": 1.0, "earned": 122.0, "balance": 1000.0, "turn": _turn(), "clears": [], "fruits": {"balance": 111.0, "paid": [{"id": "hard_first", "amount": 10.0}]}}
	wallet.note_receipt(SERVER, ME, ROOM, HASH, receipt)
	_check(fruits.unlocks(SERVER, ME).size() == 0, "The goal was paid on the first read already, so the receipt brings no new toast for it")
	# A goal newly paid by this receipt: news until its line shows.
	var fresh := {"schema_version": 1.0, "earned": 122.0, "balance": 1000.0, "turn": _turn(), "clears": [], "fruits": {"balance": 121.0, "paid": [{"id": "duel_win_ten", "amount": 20.0}]}}
	var second := "2" + HASH.substr(1)
	wallet.note_receipt(SERVER, ME, ROOM, second, fresh)
	_check(fruits.unlocks(SERVER, ME).map(func(goal: Dictionary) -> String: return goal.id) == ["duel_win_ten"], "A goal the receipt paid waits to be shown")
	var scope := {"server": SERVER, "owner": ME}
	var line: Control = ResultLine.once({}, "turn_saved", scope, {"room_id": ROOM, "recording_hash": second}, Color.WHITE, wallet)
	var plum := line.find_children("FruitResultLine", "PanelContainer", true, false) if line != null else []
	_check(plum.size() == 1, "The result card has one plum line for the goal")
	var texts: Array = (plum[0] as Node).find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if not plum.is_empty() else []
	_check(texts.has("Ten friend duel wins") and texts.has("20 Fruits") and texts.has("+"), "It names the goal and its Fruits after the plus: %s" % [texts])
	_check((plum[0] as Node).find_child("FruitMark", true, false) != null if not plum.is_empty() else false, "with the Fruit mark")
	_check(fruits.unlocks(SERVER, ME).is_empty(), "Its first showing marks the goal shown, so no toast says it again")
	if line != null: line.free()
	# One credit paying two goals: both lines show, and both count as shown.
	var third := "3" + HASH.substr(1)
	wallet.note_receipt(SERVER, ME, ROOM, third, {"schema_version": 1.0, "earned": 122.0, "balance": 1000.0, "turn": _turn(), "clears": [],
		"fruits": {"balance": 151.0, "paid": [{"id": "together_five", "amount": 15.0}, {"id": "hard_five", "amount": 15.0}]}})
	_check(fruits.unlocks(SERVER, ME).size() == 2, "Two goals paid by one credit both wait")
	var both: Control = ResultLine.once({}, "turn_saved", scope, {"room_id": ROOM, "recording_hash": third}, Color.WHITE, wallet)
	var lines: Array = both.find_children("*", "PanelContainer", true, false).filter(func(node: Node) -> bool: return node.has_meta("fruit_id")) if both != null else []
	_check(lines.size() == 2 and fruits.unlocks(SERVER, ME).is_empty(), "Both plum lines show and both goals count as shown, so neither toasts later")
	if both != null: both.free()
	PollenSurfaces.set_shared_for_tests(false)
	wallet.note_receipt(SERVER, ME, ROOM, "1" + HASH.substr(1), fresh)
	var plain: Control = ResultLine.build(scope, ROOM, "1" + HASH.substr(1), Color.WHITE, wallet)
	_check(plain == null or plain.find_children("FruitResultLine", "PanelContainer", true, false).is_empty(), "A build that sells nothing shows no plum line")
	if plain != null: plain.free()
	PollenSurfaces.set_shared_for_tests(true, true)
	FruitWallet.use_shared(null)

func _sunshine_card() -> void:
	var card: Control = SunshineCard.make({"left": 21, "turns": 24, "price": 20}, false)
	root.add_child(card)
	await process_frame
	_check(card.dots.golden() == 21 and card.dots.turns == 24, "A dot per turn, 21 of them golden")
	_check((card.find_child("SunshineLeft", true, false) as Label).text == "21 of 24 turns left", "It says the turns left")
	_check(card.buy_button != null and card.buy_button.disabled, "While turns are left the price button shows greyed, as board 7 draws it")
	card.free()
	var offered: Control = SunshineCard.make({"left": 0, "turns": 24, "price": 20}, true)
	root.add_child(offered)
	await process_frame
	var pressed := []
	offered.buy_pressed.connect(func(button: Button) -> void: pressed.append(button))
	_check(offered.buy_button != null and offered.buy_button.find_child("FruitMark", true, false) != null and offered.dots.golden() == 0, "With none left, the price button shows the Fruit and the price")
	offered.buy_button.pressed.emit()
	_check(pressed.size() == 1, "Its first tap registers")
	offered.free()
	# On the Pollen page: in the Turns card's foot, only while Fruits show.
	for fruits_on: bool in [true, false]:
		var page := PlayPage.new()
		root.add_child(page)
		page.render({"history": {"turns": [{"amount": 222, "at": 0, "level_id": "relay-isles", "stage_id": "relay", "role": "a", "bonuses": ["first_try"], "bloom": 1, "reason": "", "sunshine": 111}], "first_clears": [], "bank": {},
			"exchanges": [{"kind": "convert", "amount": 6000, "at": 5000}, {"kind": "reclaim", "amount": -3000, "at": 0}]},
			"fruits": fruits_on, "sunshine": {"left": 21, "turns": 24, "price": 20}, "sunshine_buyable": false})
		await process_frame
		var foot: Node = page.find_child("PollenTurnsCardFoot", true, false)
		_check((foot != null and foot.find_child("SunshineCard", true, false) != null) == fruits_on, "The Sunshine card shows at the Turns card's foot only while Fruits show (%s)" % fruits_on)
		var tag: Node = page.find_child("PollenTurnSunshine", true, false)
		var tag_text: Array = tag.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text) if tag != null else []
		_check((tag != null) == fruits_on and (not fruits_on or tag_text == ["First try · ", "Sunshine ×2"]), "The turn's tag reads 'First try · [sun] Sunshine ×2' only while Fruits show: %s" % [tag_text])
		var moved: Array = page.find_children("PollenExchangeRow*", "HBoxContainer", true, false).map(func(row: Node) -> String: return (row.get_child(0) as Label).text)
		_check(moved == (["Turned from Fruits", "Taken back with a Fruit refund"] if fruits_on else []), "Pollen moved by Fruits shows among the turns only while Fruits show: %s" % [moved])
		var order: Array = page.find_children("Pollen*Row*", "HBoxContainer", true, false).map(func(row: Node) -> String: return row.name)
		_check(not fruits_on or order == ["PollenExchangeRow0", "PollenTurnRow0", "PollenExchangeRow1"], "Newest first, by when: %s" % [order])
		page.free()

func _convert_sheet(online: Online) -> void:
	var parent := Control.new()
	parent.size = Vector2(1561, 720)
	root.add_child(parent)
	var sent := []
	var sheet: RefCounted = ConvertSheet.open(parent, {"pollen_per_fruit": 300, "step": 10}, 101, 24000, func(count: int) -> void: sent.append(count))
	await process_frame
	var texts := func() -> Dictionary:
		return {"count": sheet._count_label.text, "made": sheet._made_label.text, "fruits": sheet._fruits_after.text, "pollen": sheet._pollen_after.text, "button": sheet.confirm.text}
	_check(texts.call() == {"count": "10", "made": "3,000", "fruits": "91", "pollen": "27,000", "button": "Turn 10 Fruits into Pollen"}, "It opens at one step with the sums: %s" % [texts.call()])
	_check(sheet.less.disabled and not sheet.more.disabled, "Minus is greyed at one step")
	sheet.more.pressed.emit()
	_check(texts.call() == {"count": "20", "made": "6,000", "fruits": "81", "pollen": "30,000", "button": "Turn 20 Fruits into Pollen"}, "Plus adds one step, as board 8 draws it: %s" % [texts.call()])
	for i in range(20): sheet.more.pressed.emit()
	_check(sheet.count == 100 and sheet.more.disabled and not sheet.less.disabled, "Plus stops at the most whole steps the balance covers: %d" % sheet.count)
	sheet.confirm.pressed.emit()
	_check(sent == [100], "The button sends the count shown: %s" % [sent])
	_check(ConvertSheet.most(101, 10) == 100 and ConvertSheet.most(9, 10) == 0 and ConvertSheet.most(30, 10) == 30, "The most a balance turns, in whole steps")
	online.on = false
	online.changed.emit(false)
	await process_frame
	_check(sheet.confirm.disabled, "Offline the button greys")
	online.on = true
	online.changed.emit(true)
	await process_frame
	_check(not sheet.confirm.disabled, "and comes back with the connection")
	parent.free()

func _spends(online: Online) -> void:
	var server := Server.new()
	var host := Host.new()
	root.add_child(host)
	var flow: Node = SpendFlow.new(host)
	host.add_child(flow)
	var parent := Control.new()
	parent.size = Vector2(1561, 720)
	host.overlay.add_child(parent)
	# Sunshine with turns left: nothing offered, the plain line if asked.
	var fruits := _fruits("spend", _part(5, 21))
	flow.client = _client("spend", fruits, server)
	_check(flow.visible() and not flow.sunshine_offered(), "No Sunshine is offered while turns are left")
	flow.sunshine(parent)
	_check(host.said.back() == "Your Sunshine still has turns left." and flow.sheet() == null, "Asked anyway, it says why and opens nothing")
	# None left and 5 Fruits: offered, and the short card opens for the 15 missing.
	fruits = _fruits("spend_short", _part(5, 0))
	flow.client = _client("spend_short", fruits, server)
	_check(flow.sunshine_offered(), "With none left Sunshine is offered, whatever the balance")
	flow.sunshine(parent)
	_check(flow.sheet() != null and flow.sheet().name == "WardrobeShort", "Short of its price, the shared short card opens")
	flow._close_sheet()
	# 101 Fruits: the shared confirm card with the sun, then the spend.
	fruits = _fruits("spend_ok", _part(101, 0))
	flow.client = _client("spend_ok", fruits, server)
	flow.sunshine(parent)
	var card: Control = flow.sheet()
	_check(card != null and card.name == "WardrobeConfirm" and card.find_child("SunshineConfirmArt", true, false) != null and card.find_child("WardrobeConfirmPip", true, false) == null, "Covered, the Fruit confirm card opens with the sun in the pip's place")
	server.answer = {"ok": true, "status": 200, "data": {"schema_version": 1.0, "currency": "fruits", "balance": 24000.0, "fruit_balance": 81.0, "sunshine_left": 24.0}}
	var buy: Button = card.find_child("WardrobeConfirmBuy", true, false) if card != null else null
	if buy != null: buy.pressed.emit()
	for i in range(6): await process_frame
	_check(server.sent.size() == 1 and server.sent[0][2].kind == "sunshine" and int(server.sent[0][2].expected_cost) == 20, "Buy sends Sunshine at the price shown: %s" % [server.sent])
	_check(fruits.sunshine(SERVER, ME).left == 24 and fruits.balance(SERVER, ME) == 81, "The receipt is kept: 24 turns, 81 Fruits")
	_check(host.said.back() == "Sunshine is on for your next 24 bank turns.", "and it says so: %s" % [host.said.back()])
	# Converting: refusals read plainly; offline nothing is sent.
	server.sent.clear()
	server.answer = {"ok": false, "status": 409, "code": "pollen_price_changed"}
	flow.convert(parent)
	var sheet: Control = flow.sheet()
	_check(sheet != null and sheet.name == "FruitConvert", "Turn into Pollen opens the convert card")
	var confirm: Button = sheet.find_child("FruitConvertConfirm", true, false) if sheet != null else null
	if confirm != null: confirm.pressed.emit()
	for i in range(8): await process_frame
	_check(server.sent.size() >= 1 and server.sent[0][2].kind == "convert" and server.sent[0][2].id == "10", "It sends the count as the id: %s" % [server.sent])
	_check(host.said.back() == "The price changed. Take another look before you buy.", "A refusal reads as a plain line: %s" % [host.said.back()])
	for code: String in ["sunshine_active", "fruits_blocked", "fruits_short", "fruits_disabled", "offline", "busy", "invalid_pollen_spend"]:
		_check(not SpendFlow.error_line(code).is_empty() and not SpendFlow.error_line(code).contains("_"), "Refusal %s has a plain line" % code)
	online.on = false
	server.sent.clear()
	flow.convert(parent)
	_check(flow.sheet() == null or flow.sheet().name != "FruitConvert", "Offline the card does not open")
	_check(host.said.back() == PlayerCopy.OFFLINE_NEEDS_CONNECTION, "and the reason shows")
	online.on = true
	# A balance under one step: the short card for one step.
	fruits = _fruits("spend_few", _part(4, 0))
	flow.client = _client("spend_few", fruits, server)
	flow.convert(parent)
	_check(flow.sheet() != null and flow.sheet().name == "WardrobeShort", "Under one step, the short card opens")
	flow._close_sheet()
	host.free()

func _page() -> void:
	var server := Server.new()
	var host := Host.new()
	var history := History.new()
	history.answer = PollenHistory.checked({"schema_version": 1.0, "entries": [], "fruit_entries": [
		{"kind": "grant", "amount": 35.0, "at": 1800000300000.0, "step": 3.0},
		{"kind": "ach", "amount": 10.0, "at": 1800000200000.0, "id": "hard_first", "level_id": "relay-isles"},
		{"kind": "bundle", "amount": 25.0, "at": 1800000100000.0, "bundle": "handful"},
		{"kind": "convert", "amount": -20.0, "at": 1800000000000.0}]})
	host.pollen_client = history
	root.add_child(host)
	var spend: Node = SpendFlow.new(host)
	host.add_child(spend)
	var fruits := _fruits("page", _part(101))
	spend.client = _client("page", fruits, server)
	var flow: Node = PageFlow.new(host)
	host.add_child(flow)
	flow.spend = spend
	var routes := {}
	flow.store_route = func(from: String) -> void: routes["store"] = from
	flow.orchard_route = func(from: String) -> void: routes["orchard"] = from
	flow.pollen_route = func(from: String) -> void: routes["pollen"] = from
	flow.open("home")
	for i in range(4): await process_frame
	_check(flow.is_open() and history.reads == 1, "It opens and reads the history once")
	var page: Control = host.overlay.find_child("FruitsPage", true, false)
	var goals: Array = page.find_children("FruitGoal_*", "HBoxContainer", true, false)
	_check(goals.map(func(row: Node) -> String: return str(row.name).trim_prefix("FruitGoal_")) == IDS.slice(0, GoalsView.FEW), "The first goals in the server's order: %s" % [goals.map(func(row: Node) -> String: return row.name)])
	var first: Node = page.find_child("FruitGoal_together_first", true, false)
	_check(first.find_child("FruitGoalPaid", true, false) != null and (first.find_child("FruitGoalPlace", true, false) as Label).text == "The Relay Isles", "A paid goal has the plum badge and its place")
	var paid_texts: Array = first.find_child("FruitGoalPaidAmount", true, false).find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(paid_texts == ["+10"], "and its Fruits: %s" % [paid_texts])
	var five: Node = page.find_child("FruitGoal_together_five", true, false)
	_check(five.find_child("FruitGoalAmount", true, false) != null and five.find_child("FruitGoalSteps", true, false).filled() == 3 and five.find_child("FruitGoalSteps", true, false).goal == 5, "A goal to reach shows its amount and 3 of 5 steps")
	_check(page.find_child("FruitGoal_hard_first", true, false).find_child("FruitGoalSteps", true, false) == null, "A paid goal shows no steps")
	var link: Button = page.find_child("FruitGoalsAll", true, false)
	_check(link != null and link.accessibility_name == "All 15 goals, 340 Fruits in all", "The link names the server's count and sum: %s" % [link.accessibility_name if link != null else ""])
	link.pressed.emit()
	await process_frame
	page = host.overlay.find_child("FruitsPage", true, false)
	_check(page.find_children("FruitGoal_*", "HBoxContainer", true, false).size() == 15, "It opens every goal")
	var keepsake: Control = page.find_child("FruitGoal_keepsake_all", true, false)
	_check(keepsake.modulate.a < 0.5 and keepsake.find_child("FruitGoalSteps", true, false) == null, "A goal not counted yet is greyed, with no steps")
	var lines: Array = page.find_children("FruitLine*", "HBoxContainer", true, false).map(func(row: Node) -> String: return (row.get_child(0).get_child(0) as Label).text)
	_check(lines == ["Full Journey, month 3", "First Hard clear together", "Handful", "Turned into Pollen"], "The newest Fruit lines, named: %s" % [lines])
	var amounts: Array = page.find_children("FruitLineAmount", "Label", true, false).map(func(label: Label) -> String: return label.text)
	_check(amounts == ["+35", "+10", "+25", "−20"], "with their Fruits: %s" % [amounts])
	_check((page.find_child("FruitWalletAmount", true, false) as Label).text == "101", "The big balance")
	var buttons: Array = page.find_child("FruitWalletButtons", true, false).get_children().map(func(button: Node) -> String: return button.name)
	_check(buttons == ["FruitsPage_get", "FruitsPage_orchard", "FruitsPage_sunshine", "FruitsPage_convert"], "The board's four buttons: %s" % [buttons])
	(page.find_child("FruitsPage_get", true, false) as Button).pressed.emit()
	(page.find_child("FruitsPage_orchard", true, false) as Button).pressed.emit()
	(page.find_child("FruitsPage_sunshine", true, false) as Button).pressed.emit()
	_check(routes == {"store": "fruits", "orchard": "fruits", "pollen": "fruits"}, "Each opens its screen with Back to this page: %s" % [routes])
	flow.orchard_ready = func() -> bool: return false
	flow.pollen_ready = func() -> bool: return false
	link = page.find_child("FruitGoalsAll", true, false)
	link.pressed.emit()
	await process_frame
	page = host.overlay.find_child("FruitsPage", true, false)
	_check(page.find_child("FruitsPage_orchard", true, false) == null and page.find_child("FruitsPage_sunshine", true, false) == null, "Open the Orchard and Sunshine show only while their screens can open")
	flow.orchard_ready = Callable()
	flow.pollen_ready = Callable()
	link = page.find_child("FruitGoalsAll", true, false)
	link.pressed.emit()
	await process_frame
	page = host.overlay.find_child("FruitsPage", true, false)
	for size: Vector2i in SIZES:
		var viewport := SubViewport.new()
		viewport.size = size
		root.add_child(viewport)
		host.overlay.reparent(viewport)
		for i in range(3): await process_frame
		page = host.overlay.find_child("FruitsPage", true, false)
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		for name: String in ["FruitGoalsCard", "FruitWalletCard", "FruitWalletButtons", "FruitsPageBack"]:
			var part: Control = page.find_child(name, true, false)
			_check(part != null and screen.encloses(part.get_global_rect().grow(-0.5)), "%s stays on the %s screen: %s" % [name, size, part.get_global_rect() if part != null else Rect2()])
		var buttons_rect: Rect2 = page.find_child("FruitWalletButtons", true, false).get_global_rect()
		_check(page.find_child("FruitWalletCard", true, false).get_global_rect().encloses(buttons_rect), "The buttons stay inside the plum card at %s" % size)
		host.overlay.reparent(host)
		viewport.free()
	# No packs: no Get Fruits; Fruits off: the page closes.
	fruits.set_enabled(SERVER, ME, true, false)
	await process_frame
	page = host.overlay.find_child("FruitsPage", true, false)
	_check(page.find_child("FruitsPage_get", true, false) == null, "Get Fruits shows only while packs sell")
	fruits.set_enabled(SERVER, ME, false)
	var closed := []
	flow.back_requested.connect(func() -> void: closed.append(true))
	fruits.changed.emit(SERVER, ME)
	_check(closed == [true], "With Fruits off the page goes Back")
	host.overlay.find_child("FruitsPage", true, false).queue_free()
	await process_frame
	flow.open("home")
	_check(not flow.is_open(), "and it does not open while Fruits are hidden")
	host.free()

func _toasts() -> void:
	var host := Host.new()
	root.add_child(host)
	var fruits := _fruits("toasts", _part(101))
	fruits.note_receipt(SERVER, ME, {"fruits": {"balance": 161, "paid": [{"id": "ghost_first", "amount": 10}, {"id": "top_ten", "amount": 50}]}})
	var toasts: Node = Toasts.new(host)
	toasts.fruits = fruits
	var opened := []
	toasts.open_page = func(from: String) -> void: opened.append(from)
	host.add_child(toasts)
	host.running = true
	_check(toasts.service() == "", "Nothing while a turn is played")
	host.running = false
	host.relay_child = Node3D.new()
	_check(toasts.service() == "", "nor while a room is open")
	host.relay_child.free()
	host.relay_child = null
	_check(toasts.service() == "First time beating Our run: +10 Fruits", "The oldest goal first")
	_check(toasts.service() == "", "One at a time: nothing while its line shows")
	host.toast.up = false
	_check(toasts.service() == "First Top 10 ribbon: +50 Fruits", "then the next")
	host.toast.up = false
	_check(toasts.service() == "" and fruits.unlocks(SERVER, ME).is_empty(), "Each says once")
	host.toast.action.call()
	_check(opened == ["home"], "View opens the Fruits page")
	toasts.surfaces = PollenSurfaces.new(false)
	fruits.note_receipt(SERVER, ME, {"fruits": {"balance": 261, "paid": [{"id": "gold_leaf", "amount": 100}]}})
	_check(toasts.service() == "", "Nothing while Fruits are hidden")
	_check(not toasts._waiting, "and it stops looking until the Fruits change, so a phone without Fruits does no work each frame")
	toasts.surfaces = PollenSurfaces.new(true, true)
	fruits.changed.emit(SERVER, ME)
	_check(toasts.service() == "Gold leaf: +100 Fruits", "Once Fruits show, a goal kept from before still says itself")
	host.free()

## The in-play pill under the try pill.
func _hud_pill() -> void:
	var controls: CanvasLayer = ChapterControls.new()
	root.add_child(controls)
	await process_frame
	controls.show_sunshine(true)
	_check(controls.sunshine_pill.visible and controls.sunshine_pill.label.text == "Sunshine ×2" and controls.sunshine_pill.find_child("SunMark", true, false) != null, "The Sunshine pill shows the sun and Sunshine ×2")
	controls.show_sunshine(false)
	_check(not controls.sunshine_pill.visible, "and hides")
	controls.free()
