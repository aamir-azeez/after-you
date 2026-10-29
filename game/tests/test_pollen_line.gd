extends SceneTree
## The Pollen line after a turn on the real room screens (relay_preview.gd,
## presentation/pollen_result_line.gd), with a real room session against a fake
## server whose turn replies carry Pollen credits:
## - it lays out on one row in the checkpoint card, the waiting panel and the
##   chapter's end card, measured at the logical sizes of 1280x720, 1600x738
##   and 800x360 phones (canvas_items, expand, 1280x720 base), inside each
##   screen's scroll container; a long line wraps by words, never by letters;
## - the host and the guest each see the credit of every turn they earned on,
##   including the turn that finished the chapter;
## - a credit shows once: a redraw of the same screen keeps it, but reopening the
##   room, a pending turn or the end card never shows it again; a credit that
##   lands later (a claim) shows on the waiting screen's next draw.
const Preview = preload("res://relay_preview.gd")
const Session = preload("res://services/relay_online_session.gd")
const Catalog = preload("res://core/v2/stage_catalog.gd")
const Simulation = preload("res://core/v2/simulation_v2.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const PollenWallet = preload("res://services/pollen_wallet.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const ResultLine = preload("res://presentation/pollen_result_line.gd")

# Synthetic ids only.
const HOST := "HHHHHHHHHHHHHHHHHHHHHH"
const GUEST := "GGGGGGGGGGGGGGGGGGGGGG"
const ROOM := "40173cc9d5bee436613f7a"
const SERVER := "https://synthetic.invalid"
## Logical screen sizes: a 1280x720 phone, the owner's 1600x738 phone and an 800x360 phone.
const SIZES := [Vector2i(1280, 720), Vector2i(1561, 720), Vector2i(1600, 720)]

class MemoryStore:
	extends RefCounted
	var values: Dictionary = {}
	func load_scope(scope: String) -> Dictionary:
		return {"ok": true, "found": values.has(scope), "value": values.get(scope, {}).duplicate(true)}
	func save_scope(scope: String, value: Dictionary) -> Dictionary:
		values[scope] = JSON.parse_string(JSON.stringify(value))
		return {"ok": true}

class Identity:
	extends RefCounted
	var player := HOST
	func get_value() -> Dictionary:
		return {"ready": true, "player_id": player, "epoch": 1}

class FakeApi:
	extends Node
	var player_id := HOST
	var device_token := "synthetic-device-token"
	var base_url := SERVER
	var joined := true
	var index := 0
	var has_a := false
	var revision := 1
	var receipts: Dictionary = {}
	## recording hash -> the turn reply's `pollen` for that turn.
	var credits: Dictionary = {}
	var drop_next := false
	var responder: Callable
	func configured() -> bool:
		return true
	func request_json(method: int, path: String, body: Dictionary = {}, _still: Callable = Callable()) -> Dictionary:
		var response: Dictionary = responder.call({"method": method, "path": path, "body": body.duplicate(true), "owner": player_id})
		if drop_next and method == HTTPClient.METHOD_POST:
			drop_next = false
			return {"ok": false, "status": 0, "code": "connection_interrupted", "error": "Synthetic interrupted response."}
		return JSON.parse_string(JSON.stringify(response))

var fixtures: Dictionary = {}
var level := Catalog.relay_isles()
var checks := 0
var failures := 0
var wallet_path := ""
## Sessions read their identity through a Callable, which does not keep it alive.
var identities: Array[Identity] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for name: String in ["relay-a", "relay-b", "garden-a", "garden-b", "initial-checkpoint", "relay-checkpoint", "final-checkpoint"]:
		fixtures[name] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/v2/" + name + ".json"))
	wallet_path = "user://test-pollen-line-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode()
	PollenWallet.use_shared(PollenWallet.new(wallet_path))
	PollenSurfaces.set_shared_for_tests(true)
	await _long_line_wraps_by_words()
	await _room_flow()
	PollenWallet.use_shared(null)
	PollenSurfaces.set_shared_for_tests(null)
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(wallet_path + suffix): DirAccess.remove_absolute(wallet_path + suffix)
	await create_timer(1.0).timeout
	print("AFTER YOU POLLEN LINE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# --- The fake server ---------------------------------------------------------

## A turn credit as the server sends it (JSON numbers arrive as floats).
static func _credit(earned: float, clear: float = 0.0) -> Dictionary:
	var turn_total := earned - clear
	var turn := {"kind": "bank", "base": turn_total, "bonuses": ["first_try"], "bonus_percent": 25.0, "amount": turn_total, "bloom": 1.0, "bloom_extra": 0.0,
		"boost_percent": 0.0, "boost": 0.0, "total": turn_total}
	var clears: Array = [{"kind": "clear", "level_id": "relay-isles", "amount": clear, "boost_percent": 0.0, "boost": 0.0, "total": clear}] if clear > 0.0 else []
	return {"schema_version": 1.0, "earned": earned, "balance": earned, "turn": turn, "clears": clears}

func _snapshot(api: FakeApi, owner: String) -> Dictionary:
	var index := api.index
	var first: Variant = HOST if index == 0 else GUEST
	var second: Variant = GUEST if index == 0 else HOST
	var value := {"api_version": 2, "schema_version": 2, "room_id": ROOM, "revision": api.revision, "branch": 0, "stage_index": index, "level_id": "relay-isles", "level_version": 2, "definition_hash": Canonical.digest(level),
		"host_id": HOST, "guest_id": GUEST if api.joined else null, "checkpoint": fixtures[["initial-checkpoint", "relay-checkpoint", "final-checkpoint"][index]].duplicate(true), "a_turn_id": "t0-%d-a" % index if api.has_a else null,
		"completed_pair_ids": ["p0-0", "p0-1"].slice(0, index), "invite_expires_at": "2026-09-21T12:00:00Z", "created_at": "2026-09-14T12:00:00Z", "updated_at": "2026-09-14T12:00:00Z",
		"active_role": "complete" if index == 2 else ("b" if api.has_a else "a"), "first_player_id": null if index == 2 else first, "active_player_id": null if index == 2 else (second if api.has_a else first),
		"player_slot": "p0" if owner == HOST else "p1", "stage_id": "" if index == 2 else level.stages[index].id, "recording_a": fixtures["relay-a" if index == 0 else "garden-a"].duplicate(true) if api.has_a else null,
		"validation": "structural_client_replay_required"}
	if owner == HOST: value["invite_code"] = "A1".repeat(10)
	return value

func _server(request: Dictionary, api: FakeApi) -> Dictionary:
	var path: String = request.path
	var body: Dictionary = request.body
	var owner: String = request.owner
	if path == "/v2/capabilities":
		return _ok({"api_version": 2, "recording_version": 2, "simulation_version": 2, "mutations_enabled": true, "validation": "structural_client_replay_required", "pollen_version": 1,
			"chapters": [{"level_id": "relay-isles", "level_version": 2, "definition_hash": Canonical.digest(level), "premium": false}]})
	if path == "/v2/rooms" and request.method == HTTPClient.METHOD_GET:
		return _ok({"rooms": [_snapshot(api, owner)]})
	if path == "/v2/rooms/" + ROOM:
		return _ok(_snapshot(api, owner))
	if "/operations/" in path:
		# A receipt check answers the accepted turn without its credit, as the server does.
		var key := path.get_file()
		return _ok({"receipt": api.receipts[key], "room": _snapshot(api, owner)}) if api.receipts.has(key) else {"ok": false, "status": 404, "code": "operation_not_found"}
	if path.ends_with("/turns"):
		var key: String = body.idempotency_key
		var record: Dictionary = body.recording
		if not api.receipts.has(key):
			var stage_index := api.index
			var hash_input := body.duplicate(true)
			hash_input["operation"] = "turns"
			api.revision += 1
			api.has_a = record.role == "a"
			if record.role == "b": api.index += 1
			api.receipts[key] = {"schema_version": 2, "room_id": ROOM, "idempotency_key": key, "request_hash": Canonical.digest(hash_input), "operation": "turns", "accepted_revision": api.revision, "branch": 0,
				"stage_index": stage_index, "stage_id": record.stage_id, "turn_id": "t0-%d-%s" % [stage_index, record.role], "recording_hash": record.recording_hash,
				"pair_id": "p0-%d" % stage_index if record.role == "b" else null, "checkpoint_hash": fixtures[["initial-checkpoint", "relay-checkpoint", "final-checkpoint"][api.index]].checkpoint_hash}
		var reply := _ok({"receipt": api.receipts[key], "room": _snapshot(api, owner)})
		# rooms_api takes the credit out of the reply beside its data.
		if api.credits.has(record.recording_hash): reply["pollen"] = api.credits[record.recording_hash]
		return reply
	return {"ok": false, "status": 404, "code": "not_found", "error": "Synthetic missing feature."}

func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "status": 200, "data": data}

# --- Screens -----------------------------------------------------------------

## The room opened on `owner`'s phone, in a viewport of the first logical size.
func _open(api: FakeApi, store: MemoryStore, owner: String) -> Preview:
	api.player_id = owner
	var identity := Identity.new()
	identity.player = owner
	identities.append(identity)
	var session := Session.new(api, identity.get_value, store)
	var opened: bool = await session.load_lobby() and await session.open_room(ROOM)
	_check(opened, "The room opens on the %s's phone" % ("host" if owner == HOST else "guest"))
	var viewport := SubViewport.new()
	viewport.size = SIZES[0]
	root.add_child(viewport)
	var preview := Preview.new()
	preview.chapter_key = session.chapter_key()
	preview.online_session = session
	preview.settings = {"sound": false, "haptics": false, "reduced_motion": true, "assistance": true, "photo_prompts": false}
	viewport.add_child(preview)
	preview.set_process(false)
	preview.set_physics_process(false)
	await _settle()
	return preview

## Leaves the room as Main does: Back, then the screen goes.
func _close(preview: Preview) -> void:
	var viewport := preview.get_parent()
	preview._leave()
	viewport.remove_child(preview)
	preview.queue_free()
	viewport.queue_free()
	await _settle()

func _play(preview: Preview, name: String) -> void:
	preview._begin()
	for input: Dictionary in Simulation.expand_recording_inputs(fixtures[name]):
		preview.advance_input(input)
	preview._finish()
	if preview.mode == "bloom": preview._process(preview.COMPLETION_DURATION)
	_check(preview.mode == "review", "The turn reaches review: " + name)
	await preview._accept()
	if preview.mode == "photo":
		for button: Button in preview.find_children("*", "Button", true, false):
			if button.text in ["Skip", "Keep playing"] and button.is_visible_in_tree():
				button.pressed.emit()
				break
	await _settle()

func _settle() -> void:
	for frame in range(4): await process_frame

## The Pollen line on screen now, or null.
static func _line(preview: Preview) -> Control:
	var found: Array = preview.ui.find_children("PollenResultLine", "", true, false)
	return found[0] if not found.is_empty() and (found[0] as Control).is_visible_in_tree() else null

static func _words(line: Control) -> Array:
	return [] if line == null else line.find_children("*", "Label", true, false).map(func(label: Label) -> String: return label.text)

## The line on this screen, measured at every phone size: each of its labels
## takes one row as wide as its words, inside the screen and its scroll box.
func _check_layout(preview: Preview, redraw: Callable, context: String) -> void:
	var viewport := preview.get_parent() as SubViewport
	for size: Vector2i in SIZES:
		viewport.size = size
		redraw.call()
		await _settle()
		var line := _line(preview)
		_check(line != null, "The line is on the %s at %s" % [context, size])
		if line == null: continue
		var scroll: ScrollContainer = null
		var parent := line.get_parent()
		while parent != null and scroll == null:
			if parent is ScrollContainer: scroll = parent
			parent = parent.get_parent()
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		for label: Label in line.find_children("*", "Label", true, false):
			var font := label.get_theme_font("font")
			var width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x
			var rect := label.get_global_rect()
			_check(label.get_line_count() == 1 and label.size.x + 0.5 >= width, "'%s' lays out on one row, %d wide for %d of words (%d rows), on the %s at %s" % [label.text, label.size.x, width, label.get_line_count(), context, size])
			if label.get_parent() is HBoxContainer:
				var icon := label.get_parent().get_child(0) as Control
				_check(icon != label and absf(rect.position.x - icon.get_global_rect().end.x) <= 12.0, "'%s' sits right beside its flower or pip on the %s at %s" % [label.text, context, size])
			_check(screen.encloses(rect) and scroll != null and rect.position.x >= scroll.get_global_rect().position.x - 0.5 and rect.end.x <= scroll.get_global_rect().end.x + 0.5, "'%s' stays inside the screen and its scroll box on the %s at %s" % [label.text, context, size])
	viewport.size = SIZES[0]
	redraw.call()
	await _settle()

## A long boost line (a long nickname) in a narrow scroll box wraps by words.
func _long_line_wraps_by_words() -> void:
	var store := PollenWallet.new(wallet_path + "-narrow")
	store.set_enabled(SERVER, HOST, true)
	var credit := _credit(98.0)
	credit.turn.merge({"boost_percent": 20.0, "boost": 9.0, "boost_from": ["you", "partner"]}, true)
	store.note_receipt(SERVER, HOST, ROOM, fixtures["relay-a"].recording_hash, credit)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600, 400)
	root.add_child(viewport)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size = Vector2(300, 400)
	viewport.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	var line := ResultLine.build({"server": SERVER, "owner": HOST}, ROOM, fixtures["relay-a"].recording_hash, "Maximiliana Rosalind", Color.WHITE, store)
	_check(line != null, "The long line builds")
	if line != null:
		stack.add_child(line)
		await _settle()
		for label: Label in line.find_children("*", "Label", true, false):
			_check(label.get_line_count() <= 2 and label.size.x >= 250.0, "'%s' wraps by words in a narrow box: %d rows, %d wide" % [label.text, label.get_line_count(), label.size.x])
	viewport.queue_free()
	for suffix: String in ["", ".tmp", ".backup"]:
		if FileAccess.file_exists(wallet_path + "-narrow" + suffix): DirAccess.remove_absolute(wallet_path + "-narrow" + suffix)
	await _settle()

# --- The flow ----------------------------------------------------------------

func _room_flow() -> void:
	var api := FakeApi.new()
	api.responder = _server.bind(api)
	root.add_child(api)
	var store := MemoryStore.new()
	var wallet: RefCounted = PollenWallet.shared()
	# The host's first turn also had a lucky bloom: its row carries the flower.
	var bloom := _credit(178.0)
	bloom.turn.merge({"bloom": 2.0, "bloom_extra": 89.0}, true)
	api.credits = {fixtures["relay-a"].recording_hash: bloom, fixtures["relay-b"].recording_hash: _credit(71.0),
		fixtures["garden-b"].recording_hash: _credit(389.0, 300.0)}

	# The host's first turn, with the friend in the room: the waiting panel shows its credit.
	var host := await _open(api, store, HOST)
	_check(host.mode == "ready" and host.role == "a", "The host starts the first stage")
	await _play(host, "relay-a")
	_check(host.mode == "online_waiting" and _words(_line(host)) == ["+178 Pollen", "First try: +25%", "A lucky bloom: ×2"] and _line(host).find_child("PollenBloomFlower", true, false) != null, "The host's waiting panel shows the turn's credit: " + str(_words(_line(host))))
	await _check_layout(host, host._show_online_waiting, "host's waiting panel")
	host._show_online_waiting()
	await _settle()
	_check(_words(_line(host)) == ["+178 Pollen", "First try: +25%", "A lucky bloom: ×2"], "A redraw of the same waiting panel keeps the line")
	await _close(host)
	host = await _open(api, store, HOST)
	_check(host.mode == "online_waiting" and _line(host) == null, "Reopening the room never shows the same credit again")
	await _close(host)

	# The guest's B: the checkpoint card shows its credit.
	var guest := await _open(api, store, GUEST)
	_check(guest.mode == "ready" and guest.role == "b", "The guest follows the host's first turn")
	await _play(guest, "relay-b")
	_check(guest.mode == "checkpoint" and _words(_line(guest)) == ["+71 Pollen", "First try: +25%"], "The guest's checkpoint card shows the turn's credit: " + str(_words(_line(guest))))
	await _check_layout(guest, guest._after_accept, "guest's checkpoint card")
	guest._show_ready()
	_check(guest.mode == "ready" and guest.role == "a", "Continue starts the guest's next turn")

	# The guest's A with a lost reply: no line from the earlier turn while it is pending.
	api.drop_next = true
	await _play(guest, "garden-a")
	_check(guest.mode == "online_waiting" and not guest.journey.pending().is_empty(), "A lost reply leaves the turn pending")
	_check(_line(guest) == null, "A pending turn never shows the earlier turn's credit: " + str(_words(_line(guest))))
	await guest._online_refresh()
	await _settle()
	_check(guest.journey.pending().is_empty() and _line(guest) == null, "The receipt check confirms the turn; its credit is not known yet")
	# The claim lands later: the waiting screen shows it on its next draw, once.
	wallet.settle_claim(SERVER, GUEST, ROOM, fixtures["garden-a"].recording_hash, {"status": "credited", "receipt": _credit(64.0)})
	guest._show_online_waiting()
	await _settle()
	_check(_words(_line(guest)) == ["+64 Pollen", "First try: +25%"], "A credit that lands later shows on the waiting screen: " + str(_words(_line(guest))))
	await _close(guest)

	# The host's B finishes the chapter: the end card shows the turn and the first clear.
	host = await _open(api, store, HOST)
	_check(host.mode == "ready" and host.role == "b", "The host plays the last turn")
	await _play(host, "garden-b")
	_check(host.mode == "complete" and _words(_line(host)) == ["+389 Pollen", "First try: +25%", "First clear: +300"], "The end card shows the finishing turn's credit: " + str(_words(_line(host))))
	await _check_layout(host, host._show_completed, "host's end card")
	await _close(host)

	# The guest sees the finished room: their last credit showed already, so the end card has none.
	guest = await _open(api, store, GUEST)
	_check(guest.mode == "complete" and _line(guest) == null, "The guest's end card never repeats a credit they saw: " + str(_words(_line(guest))))
	await _close(guest)
	api.queue_free()
	await _settle()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
