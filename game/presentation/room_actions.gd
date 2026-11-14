extends RefCounted
## The in-chapter room's actions: one row per action, and where each room panel
## state shows it. relay_preview.gd draws a state by walking its slots in order;
## this table owns which actions appear, their order, their labels, their
## icons, their Room options section, when they apply and how each slot draws
## them (LOOKS). The screen's _room_action_hooks() holds each row's handler, as
## method references, so renaming a handler is a parse error.
##
## Moving a plain row is moving its id between two lists of one state in
## LAYOUT, for example from "turn" to "options" in "waiting_panel". Room options
## lists every row of a state's options slot that applies, grouped by its
## section, so a row may also sit in a panel slot of the same state.
## A widget row (the invitation code field or button, Share, Turn alerts' status
## line, Room options) has a screen hook that builds and wires it. In Room
## options the invitation code and Share answer on their own row, so they also
## have a hook that wires that row.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")

# Shared with the Friends screen and the legacy room page.
const SHARE := "Share current room"
const SHARE_SCOPE := "All friends"
const SHARED := "Shared with friends"
const STOP_SHARING := "Stop sharing room"
const ASK_FOR_REDO := PlayerCopy.REDO_ASK
const PLAY_AGAIN := PlayerCopy.REDO_PLAY_AGAIN
const KEEP_TURN := PlayerCopy.REDO_KEEP
const RETRY_REQUEST := PlayerCopy.REDO_RETRY

## id: the action.
##   button: an action_buttons.gd id (its label, icon and look), or
##   text: the label of a plain card button, primary: its cream look on a card.
##   icon: its icon on the wide room panel and in Room options (a header action
##   is icon only); a shared button brings its own.
##   section: its Room options group (SECTIONS); a row in an options slot has one.
##   bind: the arguments its handler (the screen's run hook) takes;
##   with_receipt: the handler also takes the turn receipt the row was drawn for.
##   line: a line under the row where its slot's look shows lines.
##   alert: on the panel, a coral edge while the row waits for an answer.
##   heading: where its slot's look shows headings, its label heads it, above
##   a divider.
##   when: facts the screen must report true, in order ("!" negates).
const ACTIONS := {
	"copy_code": {"text": "Copy invitation code", "icon": preload("res://assets/ui/social/copy.svg"), "section": "invite", "when": ["invited", "!joined"]},
	"copy_code_button": {"text": "Copy invitation code", "when": ["invited", "!joined"]},
	"share": {"text": SHARE, "icon": preload("res://assets/ui/social/share-network.svg"), "line": SHARE_SCOPE, "section": "invite", "when": ["share"]},
	"check_saved": {"button": "check_saved", "when": ["pending"]},
	"keep_held": {"text": PlayerCopy.RELAY_PREVIEW_D4FF2D8D4CDF, "when": ["held"]},
	"alerts": {"text": "Notifications", "heading": true, "when": ["!pending", "alerts", "!redo_accept"]},
	"notify": {"text": PlayerCopy.MAIN_C4B947AAAE59, "primary": true, "icon": preload("res://assets/ui/whats_new/bell.svg"), "section": "turns", "when": ["!pending", "notifications", "!redo_accept"]},
	"resume": {"button": "resume", "bind": ["resume"], "when": ["draft"]},
	"record": {"button": "record", "bind": ["record"], "when": ["!resume_only"]},
	"refresh": {"button": "refresh", "icon": preload("res://assets/ui/social/arrows-clockwise.svg"), "when": ["online", "!pending"]},
	"replays": {"button": "replays", "section": "turns", "when": ["online", "watchable"]},
	"local_replays": {"button": "replays", "when": ["solo", "watchable"]},
	# A friend's redo request (presentation/redo_flow.gd): one tap plays the
	# turn again, or the turn is kept. It leads the waiting panel.
	"redo_play": {"text": PLAY_AGAIN, "primary": true, "icon": preload("res://assets/ui/play.svg"), "when": ["!hard", "redo", "redo_accept"]},
	"redo_keep": {"text": KEEP_TURN, "when": ["!hard", "redo", "redo_accept"]},
	# The second player asks; then the row says what became of it (redo_status).
	"redo": {"text": ASK_FOR_REDO, "icon": preload("res://assets/ui/whats_new/people.svg"), "when": ["!hard", "redo", "redo_ask"]},
	# Its row (a widget) reads "Asked Sam" or "Sam kept their turn"; the label names the row.
	"redo_status": {"text": ASK_FOR_REDO, "when": ["!hard", "redo", "redo_answered"]},
	# A request or answer whose reply was lost: its recovery screen (redo_screen.gd).
	"redo_retry": {"text": RETRY_REQUEST, "icon": preload("res://assets/ui/retry.svg"), "alert": true, "when": ["redo_unsettled"]},
	"solo_redo": {"text": PlayerCopy.SOLO_REDO_ACTION, "when": ["!hard", "solo_redo"]},
	"photo": {"text": "Photo for your last contribution", "icon": preload("res://assets/ui/room/camera.svg"), "section": "turns", "with_receipt": true, "when": ["photo"]},
	"checkpoints": {"button": "retry", "when": ["!hard", "solo"]},
	# A finished solo hard run starts again from its first stage (services/hard_mode.gd).
	"hard_again": {"text": PlayerCopy.HARD_AGAIN, "primary": true, "when": ["hard", "solo"]},
	"new_room": {"text": "New room", "primary": true, "when": ["online"]},
	"restart": {"text": "Restart chapter", "primary": true, "when": ["!hard", "restart"]},
	# A room partner who is not a friend yet: the ordinary friend request
	# (services/partner_friends.gd), then "Request sent" until they answer.
	"add_friend": {"text": PlayerCopy.ROOM_ADD_FRIEND, "icon": preload("res://assets/ui/social/plus.svg"), "section": "partner", "when": ["online", "partner_addable"]},
	"friend_requested": {"text": PlayerCopy.ROOM_FRIEND_REQUESTED, "icon": preload("res://assets/ui/check.svg"), "section": "partner", "when": ["online", "partner_requested"]},
	"about": {"text": "About this chapter", "icon": preload("res://assets/ui/social/info.svg"), "section": "chapter", "when": ["about"]},
	"safety": {"text": "Report or block player", "icon": preload("res://assets/ui/room/flag.svg"), "section": "safety", "when": ["safety"]},
	"room_options": {"text": "Room options", "icon": preload("res://assets/ui/room/dots.svg"), "when": ["options"]},
	"your_rooms": {"text": "Your rooms", "icon": preload("res://assets/ui/room/door-exit.svg"), "when": []},
	"back": {"button": "back", "when": []},
}

## Room options groups, in order: the heading and the sheet column each sits
## in. danger draws the section's rows in the coral warning colour.
const SECTIONS := {
	"invite": {"title": PlayerCopy.ROOM_OPTIONS_INVITE, "column": 0},
	"turns": {"title": PlayerCopy.ROOM_OPTIONS_TURNS, "column": 1},
	"partner": {"title": PlayerCopy.ROOM_OPTIONS_PARTNER, "column": 0},
	"chapter": {"title": PlayerCopy.ROOM_OPTIONS_CHAPTER, "column": 0},
	"safety": {"title": PlayerCopy.ROOM_OPTIONS_SAFETY, "column": 1, "danger": true},
}

## How a slot draws its rows. Every card slot draws "card"; a panel slot draws
## its own. Pairs are [normal, short screen].
##   icon: the row's icon beside its label; icon_only: the icon alone;
##   cream: the primary look; height: the row's height; field, field_font and
##   copy_width: the invitation code field's height, text size and its Copy
##   button's width; fill: rows share the line's width; line and heading: the
##   row's line and heading (ACTIONS) show.
const LOOKS := {
	"card": {"height": [50, 50], "field": [52, 52], "field_font": [20, 20], "copy_width": [140, 140], "line": true, "heading": true},
	"header": {"icon_only": true},
	"status": {},
	"invite": {"icon": true, "height": [64, 54], "field": [56, 50], "field_font": [18, 18], "copy_width": [124, 124]},
	"primary": {"icon": true, "cream": true, "height": [64, 54]},
	"turn": {"icon": true, "height": [52, 52]},
	"pair": {"icon": true, "fill": true, "height": [52, 52]},
}

## state: {slot: action ids in screen order}. A state is drawn slot by slot.
## Panel states (the wide side panel of an online room) use:
##   header: icons in the panel's title row; status: lines under the waiting
##   heading; invite: under the friend strip; primary: the cream actions;
##   turn: outlined rows; pair: the last line, whose rows share it; options:
##   the Room options sheet.
## A panel state is one column of the owner's mapping: my turn, my turn before
## the friend joins, waiting, waiting before the friend joins, and a sent turn
## with no receipt yet (panel_state picks it).
## Card states are the centred card (solo chapters, and online rooms on a
## narrow screen) and use invite, turn and, after the sync status line, more.
const LAYOUT := {
	"ready_panel": {
		"header": ["refresh"],
		"primary": ["resume", "record"],
		"turn": ["redo", "redo_status", "redo_retry"],
		"pair": ["room_options"],
		"options": ["share", "replays", "photo", "add_friend", "friend_requested", "about", "safety"],
	},
	"ready_panel_invite": {
		"header": ["refresh"],
		"invite": ["copy_code", "share"],
		"primary": ["resume", "record"],
		"pair": ["room_options"],
		"options": ["copy_code", "share", "photo", "about"],
	},
	"waiting_panel": {
		"header": ["refresh"],
		"status": ["alerts"],
		"primary": ["redo_play", "notify"],
		"turn": ["redo_keep", "redo_retry"],
		"pair": ["room_options", "your_rooms"],
		"options": ["share", "notify", "replays", "photo", "add_friend", "friend_requested", "about", "safety"],
	},
	"waiting_panel_invite": {
		"header": ["refresh"],
		"status": ["alerts"],
		"invite": ["copy_code"],
		"primary": ["share"],
		"pair": ["room_options", "your_rooms"],
		"options": ["copy_code", "share", "notify", "photo", "about"],
	},
	"waiting_panel_pending": {
		"invite": ["copy_code"],
		"primary": ["check_saved"],
		"turn": ["keep_held"],
		"pair": ["room_options", "your_rooms"],
		"options": ["copy_code", "share", "replays", "add_friend", "friend_requested", "about", "safety"],
	},
	"ready_card": {
		"invite": ["copy_code_button", "share"],
		"turn": ["resume", "record", "redo", "redo_status", "redo_retry", "refresh", "local_replays", "restart", "solo_redo", "add_friend", "friend_requested", "safety", "photo", "back"],
	},
	"waiting_card": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "redo_play", "redo_keep", "redo_retry", "alerts", "notify", "refresh", "share"],
		"more": ["replays", "add_friend", "friend_requested", "safety", "photo", "back"],
	},
	"complete": {
		"turn": ["hard_again", "replays", "local_replays", "checkpoints", "new_room", "solo_redo", "add_friend", "friend_requested", "safety", "photo", "back"],
	},
}

## Cards outside the room panel (pause, review) add these rows when they apply.
const REDO_ACTIONS := ["redo", "redo_status", "redo_retry", "solo_redo"]

## The wide panel's state for a room screen, "ready" or "waiting".
static func panel_state(screen: String, fact: Callable) -> String:
	if screen == "waiting" and fact.call("pending", ""): return "waiting_panel_pending"
	var invite: bool = fact.call("invited", "") and not fact.call("joined", "")
	return screen + "_panel" + ("_invite" if invite else "")

static func is_panel(state: String) -> bool:
	return state.contains("_panel")

## The look of one slot of one state, its pairs resolved for a short screen
## (see LOOKS). Rows drawn outside a state take no look.
static func look(state: String, slot: String, short: bool) -> Dictionary:
	var resolved := {"short": short}
	var source: Dictionary = LOOKS.get(slot, {}) if is_panel(state) else LOOKS.card
	for key: String in source: resolved[key] = source[key][1 if short else 0] if source[key] is Array else source[key]
	return resolved

## The ids of one slot of one state that apply now. `fact(name, state)`
## answers a fact with a bool; facts are read in row order and only as far as
## needed.
static func shown(state: String, slot: String, fact: Callable) -> Array[String]:
	var ids: Array[String] = []
	for id: String in LAYOUT.get(state, {}).get(slot, []):
		if applies(id, fact, state): ids.append(id)
	return ids

## Room options for one state: two columns, each a list of
## {"section": name, "ids": [...]}, sections in SECTIONS order and rows in the
## state's options order. Empty sections are left out.
static func option_columns(state: String, fact: Callable) -> Array:
	var ids := shown(state, "options", fact)
	var columns := [[], []]
	for section: String in SECTIONS:
		var rows := ids.filter(func(id: String): return ACTIONS[id].get("section", "") == section)
		if not rows.is_empty(): columns[SECTIONS[section].column].append({"section": section, "ids": rows})
	return columns

static func applies(id: String, fact: Callable, state: String = "") -> bool:
	for name: String in ACTIONS[id].when:
		if name.begins_with("!") == bool(fact.call(name.trim_prefix("!"), state)): return false
	return true

static func label(id: String, fact: Callable = Callable()) -> String:
	var row: Dictionary = ACTIONS[id]
	return str(ActionButtons.DEFINITIONS[row.button].label) if row.has("button") else str(row.text)

## A row's icon: its own, or its shared button's.
static func icon(id: String) -> Texture2D:
	var row: Dictionary = ACTIONS[id]
	if row.has("icon"): return row.icon
	return ActionButtons.ICONS[ActionButtons.DEFINITIONS[row.button].icon] if row.has("button") else null
