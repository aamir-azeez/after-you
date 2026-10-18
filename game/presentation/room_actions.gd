extends RefCounted
## The in-chapter room's actions: one row per action, and where each room panel
## state shows it. relay_preview.gd draws a state by walking its slots in order;
## this table owns which actions appear, their order, their labels, their
## icons, their Room options section, their handlers, when they apply and how
## each slot draws them (LOOKS).
##
## Moving a plain row is moving its id between two lists of one state in
## LAYOUT, for example from "turn" to "options" in "waiting_panel". Room options
## lists every row of a state's options slot that applies, grouped by its
## section, so a row may also sit in a panel slot of the same state.
## A widget row (the invitation code field or button, Share, Turn alerts' status
## line, Room options) names the screen method that builds and wires it. In Room
## options the invitation code and Share answer on their own row, so they name
## the screen method that wires that row.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")

# Shared with the Friends screen and the legacy room page.
const SHARE := "Share current room"
const SHARE_SCOPE := "All friends"
const SHARED := "Shared with friends"
const STOP_SHARING := "Stop sharing room"
const REDO_REQUESTED := "Redo requested"
const ASK_FOR_REDO := "Ask for redo"
const TURN_REQUESTS := "Turn requests"

## id: the action.
##   button: an action_buttons.gd id (its label, icon and look), or
##   text: the label of a plain card button, primary: its cream look on a card.
##   icon: its icon on the wide room panel and in Room options (a header action
##   is icon only); a shared button brings its own.
##   section: its Room options group (SECTIONS); a row in an options slot has one.
##   run: the screen's handler method, bind: its arguments; with_receipt: the
##   handler also takes the turn receipt the row was drawn for.
##   widget: the screen method that builds and wires this row (no run). It
##   takes (parent, id, facts, look) and returns the row's button, if any.
##   option: the screen method that wires its Room options row, taking the row
##   and the id; without one the row runs `run` once the sheet closes.
##   drawn: a screen method told about the row's button once it is drawn.
##   line: a line under the row where its slot's look shows lines.
##   heading: where its slot's look shows headings, its label heads it, above
##   a divider.
##   when: facts the screen must report true, in order ("!" negates).
const ACTIONS := {
	"copy_code": {"text": "Copy invitation code", "icon": preload("res://assets/ui/social/copy.svg"), "section": "invite", "widget": "_add_invitation_code_row", "option": "_wire_copy_code_option", "when": ["invited", "!joined"]},
	"copy_code_button": {"text": "Copy invitation code", "widget": "_add_copy_code_button", "when": ["invited", "!joined"]},
	"share": {"text": SHARE, "icon": preload("res://assets/ui/social/share-network.svg"), "line": SHARE_SCOPE, "section": "invite", "widget": "_add_share_row", "option": "_wire_share_option", "when": ["share"]},
	"check_saved": {"button": "check_saved", "run": "_online_refresh", "when": ["pending"]},
	"keep_held": {"text": PlayerCopy.RELAY_PREVIEW_D4FF2D8D4CDF, "run": "_keep_held_turn", "when": ["held"]},
	"alerts": {"text": "Notifications", "heading": true, "widget": "_add_alerts_status", "when": ["!pending", "alerts"]},
	"notify": {"text": PlayerCopy.MAIN_C4B947AAAE59, "primary": true, "icon": preload("res://assets/ui/whats_new/bell.svg"), "section": "turns", "run": "_enable_turn_notifications", "drawn": "_track_notify_offer", "when": ["!pending", "notifications"]},
	"resume": {"button": "resume", "run": "_turn_tap", "bind": ["resume"], "drawn": "_track_turn_button", "when": ["draft"]},
	"record": {"button": "record", "run": "_turn_tap", "bind": ["record"], "drawn": "_track_turn_button", "when": []},
	"refresh": {"button": "refresh", "icon": preload("res://assets/ui/social/arrows-clockwise.svg"), "run": "_online_refresh", "when": ["online", "!pending"]},
	"replays": {"button": "replays", "section": "turns", "run": "_play_replays", "when": ["online", "watchable"]},
	"local_replays": {"button": "replays", "run": "_show_local_replays", "when": ["solo", "watchable"]},
	"redo_answer": {"text": REDO_REQUESTED, "icon": preload("res://assets/ui/retry.svg"), "section": "turns", "run": "_open_redo", "drawn": "_announce_pending_redo", "when": ["redo", "redo_accept"]},
	"redo": {"text": ASK_FOR_REDO, "icon": preload("res://assets/ui/retry.svg"), "section": "turns", "run": "_open_redo", "when": ["redo", "!redo_accept"]},
	"solo_redo": {"text": PlayerCopy.SOLO_REDO_ACTION, "run": "_confirm_solo_redo", "when": ["solo_redo"]},
	"photo": {"text": "Photo for your last contribution", "icon": preload("res://assets/ui/room/camera.svg"), "section": "turns", "run": "_offer_recent_photo", "with_receipt": true, "when": ["photo"]},
	"checkpoints": {"button": "retry", "run": "_choose_local_checkpoint", "when": ["solo"]},
	"new_room": {"text": "New room", "primary": true, "run": "_create_another_room", "when": ["online"]},
	"restart": {"text": "Restart chapter", "primary": true, "run": "_confirm_restart_chapter", "when": ["restart"]},
	"about": {"text": "About this chapter", "icon": preload("res://assets/ui/social/info.svg"), "section": "chapter", "run": "_show_waiting_details", "when": ["about"]},
	"safety": {"text": "Report or block player", "icon": preload("res://assets/ui/room/flag.svg"), "section": "safety", "run": "_open_safety", "when": ["safety"]},
	"room_options": {"text": "Room options", "icon": preload("res://assets/ui/room/dots.svg"), "widget": "_add_room_options_button", "when": ["options"]},
	"your_rooms": {"text": "Your rooms", "icon": preload("res://assets/ui/room/door-exit.svg"), "run": "_leave", "when": []},
	"back": {"button": "back", "run": "_leave", "when": []},
}

## Room options groups, in order: the heading and the sheet column each sits
## in. danger draws the section's rows in the coral warning colour.
const SECTIONS := {
	"invite": {"title": PlayerCopy.ROOM_OPTIONS_INVITE, "column": 0},
	"turns": {"title": PlayerCopy.ROOM_OPTIONS_TURNS, "column": 1},
	"chapter": {"title": PlayerCopy.ROOM_OPTIONS_CHAPTER, "column": 0},
	"safety": {"title": PlayerCopy.ROOM_OPTIONS_SAFETY, "column": 1, "danger": true},
}

## How a slot draws its rows. Every card slot draws "card"; a panel slot draws
## its own. Pairs are [normal, short screen].
##   icon: the row's icon beside its label; icon_only: the icon alone;
##   cream: the primary look; height: the row's height; field: the invitation
##   code field's height; fill: rows share the line's width; line and heading:
##   the row's line and heading (ACTIONS) show.
const LOOKS := {
	"card": {"height": [50, 50], "field": [52, 52], "line": true, "heading": true},
	"header": {"icon_only": true},
	"status": {},
	"invite": {"icon": true, "height": [64, 54], "field": [56, 50]},
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
		"turn": ["redo_answer"],
		"pair": ["room_options"],
		"options": ["share", "redo_answer", "redo", "replays", "photo", "about", "safety"],
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
		"primary": ["notify"],
		"turn": ["redo_answer"],
		"pair": ["room_options", "your_rooms"],
		"options": ["share", "notify", "redo_answer", "redo", "replays", "photo", "about", "safety"],
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
		"options": ["copy_code", "share", "replays", "about", "safety"],
	},
	"ready_card": {
		"invite": ["copy_code_button", "share"],
		"turn": ["resume", "record", "refresh", "local_replays", "restart", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
	"waiting_card": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "alerts", "notify", "redo_answer", "redo", "refresh", "share"],
		"more": ["replays", "safety", "photo", "back"],
	},
	"complete": {
		"turn": ["replays", "local_replays", "checkpoints", "new_room", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
}

## Cards outside the room panel (pause, review) add these rows when they apply.
const REDO_ACTIONS := ["redo_answer", "redo", "solo_redo"]

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
	if id == "redo" and fact.is_valid(): return redo_label(false, fact.call("my_turn", ""))
	return str(ActionButtons.DEFINITIONS[row.button].label) if row.has("button") else str(row.text)

## A row's icon: its own, or its shared button's.
static func icon(id: String) -> Texture2D:
	var row: Dictionary = ACTIONS[id]
	if row.has("icon"): return row.icon
	return ActionButtons.ICONS[ActionButtons.DEFINITIONS[row.button].icon] if row.has("button") else null

## A redo request button's label, for the online room and the legacy room page.
static func redo_label(can_accept: bool, my_turn: bool) -> String:
	return REDO_REQUESTED if can_accept else ASK_FOR_REDO if my_turn else TURN_REQUESTS
