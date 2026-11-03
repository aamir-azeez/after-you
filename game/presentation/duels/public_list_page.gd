extends "res://presentation/duels/duel_page_base.gd"
## The public duels list (board 2): every open duel with a free spot, newest
## first or almost full first, on every chapter or one. "Joining as" switches
## between Alone and With your partner, and each row greys (never hides) when
## you can't join it as you are, with the reason under its button (services/
## public_duel_spots.gd greyed, the server's own rule). A row's lit ring is the
## spot a join would give you (spot_for); tapping any open ring joins there.
## Join and the rings only say what was tapped: the flow (public_duels_flow.gd)
## asks with the join card and does the request, and a spot someone took first
## comes back here through update_row with its note.
##
## The list reads when it opens and when it is pulled down from the top, never
## on a timer; Show more reads the next page. Taps wait through a BusyTapGate, so
## a first tap always registers and a second one waits.
const BusyTapGate = preload("res://presentation/busy_tap_gate.gd")
const Spots = preload("res://services/public_duel_spots.gd")
const Seats = preload("res://presentation/duels/public_seats.gd")
const Registry = preload("res://services/chapter_registry.gd")
const RoomChapterTitle = preload("res://services/room_chapter_title.gd")
const PLUS_ICON = preload("res://assets/ui/social/plus.svg")
const CHEVRON_ICON = preload("res://assets/ui/social/chevron-down.svg")
## How far a drag from the list's top pulls it before it reads again.
const PULL_PX := 110.0

signal post_requested(control: Control)
## The list should read again from its first page (a pull, a filter or a sort).
signal refresh_requested
signal more_requested(control: Control)
## A join: `seat` 0 to 3, or -1 for the spot the server picks.
signal join_requested(row: Dictionary, seat: int, control: Control)
signal joining_changed(joining: String)

## Your party partner's name, or "" without an intact party (no With switch then).
var partner_name := ""
## Your partner's look, for their pip on the With switch.
var partner_look: Dictionary = {}
## "alone" or "party".
var joining := Spots.ALONE
## "all" or a board key, and "newest" or "almost_full".
var scope := "all"
var sort := "newest"
## [[board key, chapter key]] the chapter menu offers, in the Chapters order.
var boards: Array = []
## (row) -> {chapter_open, partner_on, at_limit}: what the phone knows that greys a row.
var known: Callable
## The shared limit, for its greyed line.
var limit := 10
var _rows: Array = []
var _notes: Dictionary = {}
var _state := "loading"
var _next := -1
var _list: VBoxContainer
var _scroll: ScrollContainer
var _filters: HBoxContainer
var _gate: BusyTapGate
var _pull_from := Vector2.INF
var _pulled := 0.0

func page_name() -> String: return "PublicList"
func title_text() -> String: return PlayerCopy.PUBLIC_DUELS_TITLE
func subtitle_text() -> String: return PlayerCopy.PUBLIC_DUELS_SUBTITLE

func header_action() -> Control:
	var post := Kit.button(PlayerCopy.PUBLIC_DUELS_POST, Callable(), false, 56)
	post.name = "PublicPost"
	post.custom_minimum_size.x = 220
	Kit.icon_on(post, PLUS_ICON, false, 22)
	post.pressed.connect(func() -> void: post_requested.emit(post))
	return post

func opened() -> void:
	_gate = BusyTapGate.new(root)

## A tap that waits for its work, as the lobby's do.
func tap(control: Control, run: Callable) -> void:
	await _gate.tap(control, "...", Callable(), run, alive)

## A page of rows from the flow: the first page replaces the list, a later one adds to it.
func show_rows(rows: Array, next: int, append: bool = false) -> void:
	if append: _rows.append_array(rows)
	else:
		_rows = rows.duplicate()
		_notes.clear()
	_next = next
	_state = "ready"
	if is_instance_valid(_list): _render_list()

## The read failed: a list already shown stays, with nothing new.
func show_failed() -> void:
	if _state != "ready": _state = "failed"
	if is_instance_valid(_list): _render_list()

## One row as it is now (a spot just taken): `row` {} takes it off the list. `note` shows under it.
func update_row(duel_id: String, row: Dictionary, note: String = "") -> void:
	for index in range(_rows.size()):
		if _rows[index].duel_id != duel_id: continue
		if row.is_empty(): _rows.remove_at(index)
		else: _rows[index] = row
		break
	if not note.is_empty() and not row.is_empty(): _notes[duel_id] = note
	if is_instance_valid(_list): _render_list()

func rows() -> Array:
	return _rows

## The page Show more reads next, or -1 at the end.
func next_page() -> int:
	return _next

func _build() -> void:
	_filters = HBoxContainer.new()
	_filters.name = "PublicFilters"
	_filters.add_theme_constant_override("separation", 10)
	body.add_child(_filters)
	var panel := Kit.panel("PublicListPanel", Kit.PANEL_FILL, Kit.PANEL_EDGE, 18, 10.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(panel)
	_scroll = ScrollContainer.new()
	_scroll.name = "PublicListScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeRules.touch_scroll(_scroll)
	panel.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "PublicRows"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	_scroll.add_child(_list)
	_render_filters()
	_render_list()

func _render_filters() -> void:
	Kit.clear(_filters)
	_filters.add_child(Kit.text(PlayerCopy.PUBLIC_JOINING_AS, 17, UiTokens.SOFT))
	_filters.add_child(_chip("JoinAlone", PlayerCopy.PUBLIC_ALONE, joining == Spots.ALONE, func() -> void: _set_joining(Spots.ALONE), Kit.pip(Vector2(24, 28), Kit.FIRST_PIP, true)))
	if not partner_name.is_empty():
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 0)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(Kit.pip(Vector2(22, 26), Kit.FIRST_PIP, true))
		pair.add_child(Kit.pip(Vector2(22, 26), Kit.SECOND_PIP, false, partner_look))
		_filters.add_child(_chip("JoinParty", PlayerCopy.PUBLIC_WITH % partner_name, joining == Spots.PARTY, func() -> void: _set_joining(Spots.PARTY), pair))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filters.add_child(spacer)
	var chapters := MenuButton.new()
	chapters.name = "PublicChapters"
	chapters.text = _scope_title()
	chapters.flat = false
	chapters.custom_minimum_size = Vector2(0, 44)
	chapters.icon = CHEVRON_ICON
	chapters.expand_icon = true
	chapters.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chapters.add_theme_constant_override("icon_max_width", 16)
	ThemeRules.secondary(chapters)
	var menu := chapters.get_popup()
	menu.add_item(PlayerCopy.PUBLIC_ALL_CHAPTERS, 0)
	for index in range(boards.size()): menu.add_item(_chapter_title(str(boards[index][1])), index + 1)
	menu.id_pressed.connect(func(id: int) -> void: _set_scope("all" if id == 0 else str(boards[id - 1][0])))
	_filters.add_child(chapters)
	var sorts := HBoxContainer.new()
	sorts.add_theme_constant_override("separation", 0)
	sorts.add_child(_chip("SortNewest", PlayerCopy.PUBLIC_NEWEST, sort == "newest", func() -> void: _set_sort("newest")))
	sorts.add_child(_chip("SortAlmostFull", PlayerCopy.PUBLIC_ALMOST_FULL, sort == "almost_full", func() -> void: _set_sort("almost_full")))
	_filters.add_child(sorts)

func _scope_title() -> String:
	for board: Array in boards:
		if board[0] == scope: return _chapter_title(str(board[1]))
	return PlayerCopy.PUBLIC_ALL_CHAPTERS

func _set_joining(value: String) -> void:
	if joining == value: return
	joining = value
	joining_changed.emit(value)
	_render_filters()
	_render_list()

func _set_scope(value: String) -> void:
	if scope == value: return
	scope = value
	_render_filters()
	refresh_requested.emit()

func _set_sort(value: String) -> void:
	if sort == value: return
	sort = value
	_render_filters()
	refresh_requested.emit()

func _render_list() -> void:
	Kit.clear(_list)
	if _state != "ready":
		_list.add_child(Kit.wrapped(PlayerCopy.PUBLIC_LIST_LOADING if _state == "loading" else PlayerCopy.PUBLIC_LIST_FAILED, 18))
		return
	if _rows.is_empty():
		ThemeRules.empty_state(_list, "open_a", PlayerCopy.PUBLIC_LIST_EMPTY_TITLE, PlayerCopy.PUBLIC_LIST_EMPTY)
		return
	for row: Dictionary in _rows: _list.add_child(_row(row))
	if _next >= 0:
		var more := Kit.button(PlayerCopy.PUBLIC_LIST_MORE, Callable(), false, 48)
		more.name = "PublicMore"
		more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		more.custom_minimum_size.x = 220
		more.pressed.connect(func() -> void: more_requested.emit(more))
		_list.add_child(more)

## Why `row` is greyed for the current Joining as, or "" (Spots.greyed with what the phone knows).
func reason_of(row: Dictionary) -> String:
	var facts: Dictionary = known.call(row) if known.is_valid() else {}
	return Spots.greyed(row, joining, facts)

func _row(row: Dictionary) -> Control:
	var reason := reason_of(row)
	var greyed := not reason.is_empty()
	var card := Kit.panel("PublicRow_" + str(row.duel_id).left(8), Kit.CARD_FILL, Kit.HIGHLIGHT_EDGE if row.mine else Kit.PANEL_EDGE, 14, 8.0)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var faded := HBoxContainer.new()
	faded.add_theme_constant_override("separation", 12)
	faded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if greyed: faded.modulate = Color(1, 1, 1, 0.45)
	line.add_child(faded)
	faded.add_child(Kit.picture(str(row.chapter), Vector2(96, 54) if compact else Vector2(112, 63), 10))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.custom_minimum_size.x = 170 if compact else 200
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	faded.add_child(words)
	words.add_child(Kit.fitted(Kit.text(_chapter_title(str(row.chapter)), 19, UiTokens.CREAM, true), 0.0, 210.0))
	words.add_child(Kit.text(posted_text(int(row.posted_ms), int(Time.get_unix_time_from_system() * 1000.0)), 14, UiTokens.SOFT))
	if compact: words.add_child(Kit.fitted(Kit.text(status_line(row, partner_name), 14, UiTokens.SOFT), 0.0, 210.0))
	# The lit ring: where Join would put you; any open ring joins there itself.
	var spot := Spots.spot_for(Spots.open_flags(row.sides), joining)
	var first := -1 if greyed else int(spot.get("seat", -1))
	var lit: Array = [] if first < 0 else [first, first + 1] if joining == Spots.PARTY else [first]
	var on_ring := func(seat: int) -> void: join_requested.emit(row, seat, card)
	faded.add_child(Seats.duel(Seats.row_seats(row), 0, 34.0 if compact else 38.0, lit, Callable() if greyed else on_ring))
	if not compact:
		var status := Kit.wrapped(status_line(row, partner_name), 15, UiTokens.SOFT)
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status.custom_minimum_size.x = 150
		faded.add_child(status)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 150 if compact else 170
	right.add_theme_constant_override("separation", 2)
	line.add_child(right)
	var join := Kit.button(PlayerCopy.PUBLIC_JOIN_WITH % partner_name if joining == Spots.PARTY else PlayerCopy.PUBLIC_JOIN, Callable(), not greyed, 44)
	join.name = "PublicJoin"
	join.size_flags_horizontal = Control.SIZE_SHRINK_END
	join.disabled = greyed
	join.pressed.connect(func() -> void: join_requested.emit(row, -1, join))
	right.add_child(join)
	var under := str(_notes.get(row.duel_id, "")) if not _notes.get(row.duel_id, "").is_empty() else reason_text(reason, partner_name, limit)
	if not under.is_empty():
		var note := Kit.wrapped(under, 13, UiTokens.MUTED)
		note.name = "PublicReason"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(note)
	return card

## The greyed line for `reason` (services/public_duel_spots.gd), or "".
static func reason_text(reason: String, partner: String, limit_count: int) -> String:
	match reason:
		Spots.MINE: return PlayerCopy.PUBLIC_REASON_MINE
		Spots.CHAPTER: return PlayerCopy.PUBLIC_REASON_CHAPTER
		Spots.PARTNER_OFF: return PlayerCopy.PUBLIC_REASON_PARTNER_OFF % partner
		Spots.LIMIT: return PlayerCopy.PUBLIC_REASON_LIMIT % limit_count
		Spots.ONE_LEFT: return PlayerCopy.PUBLIC_REASON_ONE_LEFT
		Spots.SPLIT: return PlayerCopy.PUBLIC_REASON_SPLIT
		Spots.FULL, Spots.SEAT_TAKEN: return PlayerCopy.PUBLIC_REASON_FULL
	return ""

## "Posted 4 min ago", "Posted 1 h ago", "Posted 2 days ago" or "Posted just now".
static func posted_text(posted_ms: int, now_ms: int) -> String:
	var minutes := maxi(0, (now_ms - posted_ms) / 60_000)
	if minutes < 1: return PlayerCopy.PUBLIC_POSTED_NOW
	if minutes < 60: return PlayerCopy.PUBLIC_POSTED_MIN % minutes
	if minutes < 48 * 60: return PlayerCopy.PUBLIC_POSTED_HOURS % (minutes / 60)
	return PlayerCopy.PUBLIC_POSTED_DAYS % (minutes / (24 * 60))

## How far the row's pairs are: "Kite has played 1 step", "Both pairs have played 2 steps",
## "You and Maya: 3 of 12 steps", "5 of 12 steps" or "Nobody has played yet".
static func status_line(row: Dictionary, partner: String = "") -> String:
	var sides: Array = row.sides
	for index in range(2):
		var seats: Array = sides[index].seats
		if not (seats[0].get("you", false) or seats[1].get("you", false)): continue
		var other: Dictionary = seats[1] if seats[0].get("you", false) else seats[0]
		var who := PlayerCopy.DUEL_YOU
		if not other.open: who = PlayerCopy.PUBLIC_YOU_AND % (str(other.label) if not str(other.label).is_empty() else partner if not partner.is_empty() else PlayerCopy.PUBLIC_A_PLAYER)
		return PlayerCopy.PUBLIC_STEPS_OF % [who, int(sides[index].steps), int(row.steps)]
	var a := int(sides[0].steps)
	var b := int(sides[1].steps)
	if a > 0 and b > 0: return PlayerCopy.PUBLIC_BOTH_PLAYED % a if a == b else PlayerCopy.PUBLIC_BOTH_STARTED
	if a == 0 and b == 0: return PlayerCopy.PUBLIC_NO_STEPS
	var side: Dictionary = sides[0] if a > 0 else sides[1]
	var named: Array = side.seats.filter(func(held: Dictionary) -> bool: return not held.open)
	if named.size() == 1 and not str(named[0].label).is_empty():
		var steps := int(side.steps)
		return PlayerCopy.PUBLIC_PLAYED_ONE % named[0].label if steps == 1 else PlayerCopy.PUBLIC_PLAYED % [named[0].label, steps]
	return PlayerCopy.DUEL_STEPS % [int(side.steps), int(row.steps)]

func _chip(node_name: String, label: String, chosen: bool, action: Callable, art: Control = null) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.custom_minimum_size = Vector2(0, 44)
	button.add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := UiTokens.MINT if chosen else Color.TRANSPARENT
		var style := ThemeRules.rounded(fill.lightened(0.05) if state.begins_with("hover") and chosen else fill, 10, Color.TRANSPARENT if chosen else Kit.PANEL_EDGE)
		ThemeRules.padded(style, 12.0, 4.0)
		button.add_theme_stylebox_override(state, style)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, UiTokens.INK if chosen else UiTokens.CREAM)
	button.add_theme_stylebox_override("focus", ThemeRules.rounded(Color.TRANSPARENT, 10, UiTokens.CREAM))
	if art != null:
		var holder := MarginContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_theme_constant_override("margin_left", 8)
		holder.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		holder.add_child(art)
		button.add_child(holder)
		button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.custom_minimum_size.x = button.get_theme_font("font").get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 24.0 + art.get_combined_minimum_size().x + 16.0
	button.pressed.connect(action)
	return button

## Pull down from the top of the list: once the drag passes PULL_PX, the list reads again.
func _input(event: InputEvent) -> void:
	if not alive() or not is_instance_valid(_scroll) or Kit.showing(_modal): return
	var pressed := event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed and event.pressed:
		var at: Vector2 = event.position
		_pull_from = at if _scroll.scroll_vertical == 0 and _scroll.get_global_rect().has_point(at) else Vector2.INF
		_pulled = 0.0
	elif pressed and not event.pressed:
		var pulled := _pulled
		_pull_from = Vector2.INF
		_pulled = 0.0
		if pulled >= PULL_PX: refresh_requested.emit()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _pull_from != Vector2.INF:
		_pulled = maxf(_pulled, event.position.y - _pull_from.y)

func _chapter_title(key: String) -> String:
	return RoomChapterTitle.title(key, str(Registry.descriptor(key).get("title", key)))
