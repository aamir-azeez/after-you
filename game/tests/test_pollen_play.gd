extends SceneTree
## Pollen from play and Home's Pollen chip (pollen boards 7b and 1):
## - Home's chip (kit/pollen_chip.gd, tested in test_pollen_chip.gd): the gain
##   after earning, worked out from what a chip last showed (never after a spend,
##   none on the first chip), and no plus while the shop is off;
## - the page: loading, offline with Try again, the bank with its rules, an
##   empty bank's tail in the server's numbers, recent turns with their bonuses,
##   a bloom or why one paid a little, first clears paid or not, and the Full
##   Journey sentence left out on a build that names no Full Journey; it lays
##   out inside the screen at 1280x720, 1600x738 and 800x360;
## - the flow: opens from Home or Settings and goes back there, reads once per
##   opening, and the chip opens the page while the shop is off.
const Page = preload("res://presentation/pollen_play_page.gd")
const Flow = preload("res://presentation/pollen_play_flow.gd")
const PollenChip = preload("res://presentation/kit/pollen_chip.gd")
const PollenHistory = preload("res://services/pollen_history.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const HomeMenu = preload("res://presentation/home_menu.gd")
const HomeStage = preload("res://presentation/home_stage.gd")

const SIZES := [Vector2i(1280, 720), Vector2i(1561, 720), Vector2i(1600, 720)]

class FakeWallet:
	extends RefCounted
	var balance := 24000
	func wallet(_server: String, _owner: String) -> Dictionary:
		return {"balance": balance, "earned": balance, "bank": 15}

class FakeClient:
	extends RefCounted
	var wallet := FakeWallet.new()
	var on := true
	var answer: Dictionary = {}
	var reads := 0
	func scope() -> Dictionary:
		return {"server": "https://synthetic.invalid", "owner": "OOOOOOOOOOOOOOOOOOOOOO"} if on else {}
	func history() -> Dictionary:
		reads += 1
		await Engine.get_main_loop().process_frame
		return answer.duplicate(true)

class Host:
	extends Node
	var pollen_client := FakeClient.new()
	var mode := "home"
	var running := false
	var overlay := Control.new()
	var title_font: Font = null
	func _init() -> void:
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(overlay)
	func _clear_overlay() -> void:
		for child: Node in overlay.get_children():
			overlay.remove_child(child)
			child.queue_free()

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _page_states()
	await _flow()
	await _home_slot()
	print("AFTER YOU POLLEN PLAY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

static func _history(left: int = 15) -> Dictionary:
	return PollenHistory.checked({"schema_version": 1.0, "entries": [
		{"kind": "turn", "amount": 250.0, "at": 3.0, "level_id": "relay-isles", "stage_id": "relay", "role": "a", "bonuses": ["first_try", "gold_pace"], "bloom": 2.0},
		{"kind": "turn", "amount": 185.0, "at": 2.0, "level_id": "relay-isles", "stage_id": "garden", "role": "b", "bonuses": ["first_try"]},
		{"kind": "turn", "amount": 10.0, "at": 1.0, "level_id": "relay-isles", "stage_id": "garden", "role": "b", "reason": "repeat"}],
		"first_clears": [{"level_id": "first-steps", "price": 1200.0, "paid": 1200.0}, {"level_id": "relay-isles", "price": 1200.0}, {"level_id": "conservatory", "price": 2000.0}],
		"bank": {"left": float(left), "refill": 12.0, "cap": 36.0, "tail": [{"pay": 10.0, "turns": 36.0}, {"pay": 1.0, "turns": 64.0}]}})

func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	root.add_child(viewport)
	return viewport

func _page_states() -> void:
	for size: Vector2i in SIZES:
		var viewport := _viewport(size)
		var page := Page.new()
		viewport.add_child(page)
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": PlayerCopy.POLLEN_PLAY_LOADING, "retry": false, "history": {}})
		await _settle()
		_check(_texts(page).has(PlayerCopy.POLLEN_PLAY_LOADING) and page.find_child("PollenPlayRetry", true, false) == null, "Loading says so, with no Try again")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": PlayerCopy.POLLEN_PLAY_OFFLINE, "retry": true, "history": {}})
		await _settle()
		_check(page.find_child("PollenPlayRetry", true, false) != null, "Offline offers Try again")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": true, "status": "", "retry": false, "history": _history()})
		await _settle()
		var texts := _texts(page)
		_check((page.find_child("PollenBankLeft", true, false) as Label).text == "15" and texts.has("+12 every Monday") and texts.has("holds up to 36") and is_equal_approx((page.find_child("PollenBankBar", true, false) as ProgressBar).value, 15.0), "The bank: turns left, the Monday refill and the cap, from the server: " + str(texts))
		_check(texts.has("The Relay Isles, stage 1") and texts.has("First try · gold pace") and texts.has("The Relay Isles, stage 2") and texts.has(PlayerCopy.POLLEN_TURN_REPEAT), "Recent turns name the place, their bonuses, and why one paid a little")
		_check(page.find_children("PollenBloomTag", "", true, false).size() == 1, "A bloomed turn carries its small flower tag")
		_check(texts.has("+1,200 earned") and page.find_children("*PollenClearRow*", "", true, false).size() == 2 and texts.has(PlayerCopy.POLLEN_CLEARS_FULL_JOURNEY + " " + PlayerCopy.POLLEN_CLEARS_HARD), "First clears: paid and not, free chapters only, with the Full Journey sentence: " + str(texts))
		_check(page.find_child("PollenBankTail", true, false) == null, "A bank with turns left needs no tail line")
		_layout(page, size, "the full page")
		page.render({"chip": PollenChip.make(24000, false), "full_journey": false, "status": "", "retry": false, "history": _history(0)})
		await _settle()
		texts = _texts(page)
		var tail := page.find_child("PollenBankTail", true, false) as Label
		_check(texts.has(PlayerCopy.POLLEN_BANK_EMPTY_LINE) and tail != null and tail.text == "After the bank runs out, each turn earns 10 for the next 36 turns, then 1 for the next 64, then nothing until Monday, when the bank gains 12 more turns.", "An empty bank says what turns still earn, in the server's numbers: " + (tail.text if tail != null else "none"))
		_check(texts.has(PlayerCopy.POLLEN_CLEARS_HARD) and not texts.any(func(text: String) -> bool: return text.contains("Full Journey")), "A build that names no Full Journey leaves its sentence out")
		_layout(page, size, "the page with an empty bank")
		viewport.queue_free()
		await _settle()

## Every label inside the screen, and a short one on one row.
func _layout(page: Control, size: Vector2i, context: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	for label: Label in page.find_children("*", "Label", true, false):
		if not label.is_visible_in_tree(): continue
		var rect := label.get_global_rect()
		var inside := screen.grow(0.5).encloses(rect)
		var scroll := label.get_parent()
		while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
		if scroll != null: inside = inside or not (scroll as ScrollContainer).get_global_rect().intersects(rect)
		_check(inside, "'%s' stays inside the screen in %s at %s" % [label.text, context, size])
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF: continue
		_check(label.get_line_count() <= 4 and label.size.x >= 120.0, "'%s' wraps by words, %d wide, in %s at %s" % [label.text, label.size.x, context, size])

func _flow() -> void:
	PollenSurfaces.set_shared_for_tests(true)
	var viewport := _viewport(SIZES[1])
	var host := Host.new()
	viewport.add_child(host)
	var flow := Flow.new(host)
	host.add_child(flow)
	host.pollen_client.answer = _history()
	Flow.forget_shown()
	var back: Array = []
	flow.back_requested.connect(func(to_settings: bool) -> void: back.append(to_settings))
	flow.open_from_home()
	_check(host.mode == Flow.MODE and _texts(host.overlay).has(PlayerCopy.POLLEN_PLAY_LOADING), "Opening shows the page at once, loading")
	await _settle()
	_check(host.pollen_client.reads == 1 and _texts(host.overlay).has("+12 every Monday"), "It reads the history once and draws it")
	(host.overlay.find_child("PollenPlayBack", true, false) as Button).pressed.emit()
	flow.open_from_settings()
	await _settle()
	(host.overlay.find_child("PollenPlayBack", true, false) as Button).pressed.emit()
	_check(back == [false, true] and host.pollen_client.reads == 2, "Back goes where it opened from; each opening reads once")
	host.pollen_client.answer = {}
	flow.open_from_home()
	await _settle()
	_check(_texts(host.overlay).has(PlayerCopy.POLLEN_PLAY_OFFLINE) and host.overlay.find_child("PollenPlayRetry", true, false) != null, "A read that fails offers Try again")
	host.pollen_client.answer = _history()
	(host.overlay.find_child("PollenPlayRetry", true, false) as Button).pressed.emit()
	await _settle()
	_check(_texts(host.overlay).has("+12 every Monday"), "Try again reads again")
	_check(host.overlay.find_child("PollenChip", true, false) != null, "The page's header shows the chip")
	# Home's chip: the gain after earning, from what a chip last showed.
	var gains: Array = []
	for balance: int in [24000, 24125, 23000, 23000]:
		host.pollen_client.wallet.balance = balance
		var made := flow.chip()
		gains.append(made.gain_label.text if made.gain_label.visible else "")
		made.free()
	_check(gains == ["", "+125", "", ""], "The gain shows just after earning, never after a spend or on the first chip: " + str(gains))
	# While the shop is off it opens this page, and no plus shows.
	PollenSurfaces.set_shared_for_tests(false)
	host._clear_overlay()
	host.mode = "home"
	await _settle()
	var chip := flow.chip()
	_check(chip != null and chip.plus_icon == null, "A build that sells nothing shows the chip without its plus")
	chip.pressed.emit()
	_check(host.mode == Flow.MODE, "The chip opens Pollen from play")
	chip.free()
	host.pollen_client.on = false
	_check(flow.chip() == null and not flow.available(), "No chip and no page while the server has Pollen off")
	PollenSurfaces.set_shared_for_tests(null)
	viewport.queue_free()
	await _settle()

## Home's chip sits left of Full Journey, or in its place while it is hidden.
func _home_slot() -> void:
	for size: Vector2i in SIZES:
		var viewport := _viewport(size)
		var holder := Control.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(holder)
		var menu := HomeMenu.new()
		holder.add_child(menu)
		var noop := func() -> void: pass
		menu.build({"play": func(_button: Button) -> void: pass, "solo": noop, "friends": noop, "replays": noop, "invite": noop, "whats_new": noop, "settings": noop, "full_journey": noop}, HomeStage.heading_font())
		menu.set_pollen_chip(PollenChip.make(24000, true))
		await _settle()
		var chip := menu.pollen_slot.get_child(0) as Control
		var journey := menu.journey_offer.get_global_rect()
		_check(chip.get_global_rect().end.x <= journey.position.x - 8.0 and absf(chip.get_global_rect().get_center().y - journey.get_center().y) <= 1.0 and Rect2(Vector2.ZERO, Vector2(size)).encloses(chip.get_global_rect()), "The chip sits left of Full Journey, level with it, at %s: %s %s" % [size, chip.get_global_rect(), journey])
		menu.journey_offer.visible = false
		await _settle()
		_check(absf(chip.get_global_rect().end.x - (size.x - HomeMenu.RIGHT)) <= 1.0, "With Full Journey hidden the chip takes its place at %s" % size)
		viewport.queue_free()
		await _settle()

static func _texts(node: Node) -> Array:
	return node.find_children("*", "Label", true, false).filter(func(label: Label) -> bool: return label.is_visible_in_tree()).map(func(label: Label) -> String: return label.text)

func _settle() -> void:
	for frame in range(4): await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
