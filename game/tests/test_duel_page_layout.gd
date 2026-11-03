extends SceneTree
## The duel in progress page fits every phone and tablet: its turn card, with
## Play, View turns and Leave duel, sits whole inside the safe area with the
## page's own bottom spacing (duel_page_base.gd, SafeArea.pad), and the page
## body scrolls rather than running off the screen when it ever cannot fit.
## The other duel pages (the lobby, Party, Start a duel, Race a recorded run, a
## result with its Pollen) fit every phone height without scrolling either. Every card state
## (your turn, waiting for your partner, finished, left), in a friend duel and
## a ghost race. Synthetic ids only.
const SafeArea = preload("res://presentation/safe_area.gd")
const DuelsScreen = preload("res://presentation/duels/duels_screen.gd")
const DuelPage = preload("res://presentation/duels/duel_page.gd")
const DuelsClient = preload("res://services/duels_client.gd")
const ResultPage = preload("res://presentation/duels/duel_result_page.gd")
const PartyPage = preload("res://presentation/duels/duel_party_page.gd")
const ChallengePage = preload("res://presentation/duels/duel_challenge_page.gd")
const GhostPage = preload("res://presentation/duels/duel_ghost_page.gd")
const Registry = preload("res://services/chapter_registry.gd")
const ChapterUnlocks = preload("res://services/chapter_unlocks.gd")
const ME := "MMMMMMMMMMMMMMMMMMMMMM"
const MAYA := "AAAAAAAAAAAAAAAAAAAAAA"
const FINN := "FFFFFFFFFFFFFFFFFFFFFF"
const BOARD := "sleeping-lighthouse@2"

## [physical pixels, native insets (left, top, right, bottom), name].
const SCREENS := [
	[Vector2i(2340, 1080), Vector4.ZERO, "2340x1080 phone"],
	[Vector2i(1600, 720), Vector4.ZERO, "1600x720 phone"],
	[Vector2i(1280, 720), Vector4.ZERO, "1280x720 phone"],
	[Vector2i(2400, 1080), Vector4(110, 0, 0, 0), "2400x1080 phone, cutout left"],
	[Vector2i(2400, 1080), Vector4(0, 0, 110, 0), "2400x1080 phone, cutout right"],
	[Vector2i(2340, 1080), Vector4(0, 0, 0, 66), "2340x1080 phone, gesture bar"],
	# A thin bottom inset leaves a phone just under its full 720 units: the owner's report (Android, landscape).
	[Vector2i(2340, 1080), Vector4(0, 0, 0, 24), "2340x1080 phone, thin gesture bar"],
	[Vector2i(1600, 720), Vector4(0, 0, 0, 16), "1600x720 phone, thin gesture bar"],
	[Vector2i(2400, 1080), Vector4(110, 0, 0, 30), "2400x1080 phone, cutout left and gesture bar"],
	[Vector2i(2560, 1600), Vector4.ZERO, "Android 10-inch"],
	[Vector2i(2732, 2048), Vector4(0, 0, 0, 40), "iPad 13-inch"],
	[Vector2i(2034, 1398), Vector4(0, 252, 0, 63), "iPhone Duo outer, camera band on top"],
]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _settle() -> void:
	for i in range(4): await process_frame

func _run() -> void:
	var original := {"size": root.size, "content_scale_size": root.content_scale_size, "content_scale_mode": root.content_scale_mode,
		"content_scale_aspect": root.content_scale_aspect, "content_scale_factor": root.content_scale_factor}
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.content_scale_factor = 1.0
	for screen: Array in SCREENS:
		await _test_screen(screen[0], screen[1], screen[2])
	SafeArea.simulate(Rect2())
	SafeArea.poll(self)
	await _settle()
	for property: String in original: root.set(property, original[property])
	await _settle()
	print("AFTER YOU DUEL PAGE LAYOUT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## A running duel as the server sends it, with this phone's side as `own` says.
static func _duel(kind: String, own: Dictionary) -> Dictionary:
	var side := {"members": [ME, MAYA], "you": true, "steps": 6, "ticks": 1620, "turn": 0, "finished": false, "left": false, "check": "none", "room_id": "RRRRRRRRRRRRRRRRRRRRRR", "invite_code": "abcdefabcdefabcdefab", "hosting": true}
	side.merge(own, true)
	var wire := {"schema_version": 1, "duel_id": "d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0", "kind": kind, "board": BOARD, "status": "running", "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "result": null, "eligible": true,
		"sides": [side, {"members": [FINN, null], "you": false, "steps": 4, "ticks": 1380, "turn": 1, "finished": false, "left": false, "check": "none"}]}
	if kind == "ghost":
		wire.sides[1] = null
		wire.ghost = {"source": "developer", "entry_id": null, "rank": null, "ticks": 1470, "names": null}
	return DuelsClient.valid_view(wire)

func _test_screen(size: Vector2i, insets: Vector4, name: String) -> void:
	root.size = size
	SafeArea.simulate(Rect2(insets.x, insets.y, size.x - insets.x - insets.z, size.y - insets.y - insets.w))
	SafeArea.poll(self)
	await _settle()
	var safe := SafeArea.rect(root)
	var states := {"your turn": {}, "waiting": {"turn": 1}, "finished": {"finished": true, "steps": 12, "turn": null}, "left": {"left": true}}
	# Short names, and a partner with the longest name the game shows (services/display_names.gd MAX_LENGTH).
	for partner: String in ["Maya", "Alexandra Marigold"]:
		var lobby := DuelsScreen.new()
		lobby.me = ME
		lobby.name_of = func(id: Variant) -> String: return "You" if id == ME else partner if id == MAYA else "Finn"
		root.add_child(lobby)
		await _settle()
		for kind: String in ["friend", "ghost"]:
			for state: String in states:
				var page := DuelPage.new()
				page.me = ME
				page.name_of = lobby.name_of
				page.view = _duel(kind, states[state])
				lobby.open_overlay(page)
				await _settle()
				await _check_page(page, safe, "%s, %s %s, partner %s" % [name, kind, state, partner])
				page.close()
				await _settle()
		if partner == "Maya": await _other_pages(lobby, safe, name)
		lobby.close()
		await _settle()

## The bottom spacing the page keeps above the safe area's edge (duel_page_base.gd _layout).
static func _bottom_spacing(page: CanvasLayer, safe: Rect2) -> float:
	return float(SafeArea.centred(safe.size.y, SafeArea.PAGE_HEIGHT, 12 if page.compact else 16))

func _check_page(page: CanvasLayer, safe: Rect2, context: String) -> void:
	var card := page.root.find_child("DuelTurnCard", true, false) as Control
	_check(card != null and card.is_visible_in_tree(), "%s: the turn card shows" % context)
	if card == null: return
	var spacing := _bottom_spacing(page, safe)
	# Where the card sits as drawn, before any scrolling: whole, above the page's bottom spacing (a long name may scroll).
	if not context.ends_with("Marigold"): _check(card.get_global_rect().end.y <= safe.end.y - spacing + 1.0 and safe.grow(0.5).encloses(card.get_global_rect()), "%s: the turn card shows whole, %.1f above the safe bottom (wanted %.0f)" % [context, safe.end.y - card.get_global_rect().end.y, spacing])
	var scroll := _scroll_of(card)
	_check(scroll != null, "%s: the page body sits in a scroll" % context)
	if scroll == null: return
	var view := scroll.get_global_rect()
	# Within a unit: SafeArea.pad keeps whole units of a fractional inset.
	_check(view.position.y >= safe.position.y - 0.5 and view.end.y <= safe.end.y - spacing + 1.0, "%s: the page ends %.1f above the safe bottom, wanted at least %.0f" % [context, safe.end.y - view.end.y, spacing])
	var scrolls := scroll.get_v_scroll_bar().max_value > scroll.size.y + 0.5
	if not scrolls: _check(view.grow(0.5).encloses(card.get_global_rect()), "%s: a page that fits shows the whole turn card above the bottom spacing" % context)
	# With short names every phone and tablet fits without scrolling; a long name may scroll.
	if not context.ends_with("Marigold"): _check(not scrolls, "%s: the page fits without scrolling (%.0f of %.0f)" % [context, scroll.get_v_scroll_bar().max_value, scroll.size.y])
	var leave := page.root.find_child("DuelLeave", true, false) as Control
	var lowest: Control = leave if leave != null else card
	scroll.ensure_control_visible(lowest)
	await _settle()
	_check(view.grow(0.5).encloses(lowest.get_global_rect()), "%s: scrolled to, %s shows whole above the bottom spacing" % [context, lowest.name])
	_check(safe.grow(0.5).encloses(lowest.get_global_rect()), "%s: %s is inside the safe area" % [context, lowest.name])

## Every other duel page over `lobby`: it fits without scrolling, and every
## button and line on it shows inside the safe area.
func _other_pages(lobby: CanvasLayer, safe: Rect2, name: String) -> void:
	var chapters: Array = []
	for key: String in ChapterUnlocks.chain(): if Registry.definition(key).has("stages"): chapters.append(key)
	lobby.show_lobby(DuelsClient.valid_lobby({"schema_version": 1, "party": {"partner": MAYA, "intact": true, "invites_in": [FINN], "invite_out": null},
		"duels": [_duel_wire("friend", "d1"), _duel_wire("ghost", "d2"), _duel_wire("friend", "d3", "decided")]}))
	await _settle()
	_check_fits(lobby, safe, "%s, the lobby" % name)
	var result := ResultPage.new()
	result.me = ME
	result.name_of = lobby.name_of
	result.view = DuelsClient.valid_view(_duel_wire("friend", "d3", "decided"))
	result.pay = {"turns": 6, "plain": 600, "blooms": 120, "duel": 300, "duel_percent": 50, "boost": 60, "boost_percent": 10, "total": 1080}
	result.win_bonus = {"amount": 250, "counted": true, "reason": ""}
	var party := PartyPage.new()
	party.name_of = lobby.name_of
	party.party = {"partner": MAYA, "intact": true, "invites_in": [FINN], "invite_out": null}
	party.friends = [{"id": MAYA, "name": "Maya"}, {"id": FINN, "name": "Finn"}]
	var start := ChallengePage.new()
	start.friends = [{"id": FINN, "name": "Finn"}]
	start.chapters = chapters
	var race := GhostPage.new()
	race.chapters = chapters
	for page: CanvasLayer in [result, party, start, race]:
		lobby.open_overlay(page)
		await _settle()
		if page == start:
			start._pick_friend(FINN)
			start._pick_chapter(BOARD)
		if page == race: race.show_ghosts([{"board": BOARD, "developer": 1470, "top": [{"entry_id": "e1".repeat(16), "ticks": 1400, "rank": 1, "names": null}]}])
		await _settle()
		_check_fits(page, safe, "%s, %s" % [name, page.page_name()])
		page.close()
		await _settle()

func _check_fits(page: CanvasLayer, safe: Rect2, context: String) -> void:
	var scroll := page.root.find_child(page.page_name() + "Scroll", true, false) as ScrollContainer
	_check(scroll != null and scroll.get_v_scroll_bar().max_value <= scroll.size.y + 0.5, "%s: fits without scrolling (%.0f of %.0f)" % [context, scroll.get_v_scroll_bar().max_value if scroll != null else -1.0, scroll.size.y if scroll != null else -1.0])
	_check_inside(page.root, safe, context)

## Buttons and lines inside the safe area, past any list that scrolls with more to show.
func _check_inside(node: Node, safe: Rect2, context: String) -> void:
	var control := node as Control
	if control is ScrollContainer and (control.get_v_scroll_bar().max_value > control.size.y + 0.5 or control.get_h_scroll_bar().max_value > control.size.x + 0.5): return
	if control != null and control.is_visible_in_tree() and (control is Button or control is Label) and control.size.x > 0.0:
		_check(safe.grow(0.5).encloses(control.get_global_rect()), "%s: %s is inside the safe area (%s)" % [context, control.name, control.get_global_rect()])
	for child: Node in node.get_children():
		_check_inside(child, safe, context)

## A duel as the server sends it, its id `id` repeated.
static func _duel_wire(kind: String, id: String, status: String = "running") -> Dictionary:
	var decided := status == "decided"
	var wire := {"schema_version": 1, "duel_id": id.repeat(16), "kind": kind, "board": BOARD, "status": status, "steps": 12,
		"created_ms": 1, "accepted_ms": 2, "updated_ms": 3, "mine": 0, "ghost": null, "eligible": true,
		"result": {"outcome": "won", "reason": "faster", "margin_ticks": 720, "decided_ms": 9} if decided else null,
		"sides": [{"members": [ME, MAYA], "you": true, "steps": 12 if decided else 6, "ticks": 3240, "turn": null if decided else 0, "finished": decided, "left": false, "check": "passed" if decided else "none", "room_id": "RRRRRRRRRRRRRRRRRRRRRR", "invite_code": "abcdefabcdefabcdefab", "hosting": true},
			{"members": [FINN, null], "you": false, "steps": 12 if decided else 4, "ticks": 3960, "turn": null if decided else 1, "finished": decided, "left": false, "check": "passed" if decided else "none"}]}
	if kind == "ghost":
		wire.sides[1] = null
		wire.ghost = {"source": "developer", "entry_id": null, "rank": null, "ticks": 1470, "names": null}
	return wire

static func _scroll_of(control: Control) -> ScrollContainer:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: return ancestor
		ancestor = ancestor.get_parent()
	return null
