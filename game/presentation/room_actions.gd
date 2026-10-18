extends RefCounted
## The in-chapter room's actions: one row per action, and where each room panel
## state shows it. relay_preview.gd draws a state by walking its slots in order;
## this table owns which actions appear, their order, their labels, their
## handlers and when they apply.
##
## Moving a plain row is moving its id between two lists of one state in
## LAYOUT, for example from "turn" to "options" in "waiting_panel". A custom row
## (the invitation code, Share, Room options, Your rooms) brings its own widget
## and wiring from the screen, so it may sit only in an invite or turn slot.
## A few looks stay in the screen's code: the wide ready panel's taller Record
## and icon Share, the invitation code field, and the Notifications heading
## and hint around Notify.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const ActionButtons = preload("res://presentation/action_buttons.gd")

# Shared with the Friends screen and the legacy room page.
const SHARE := "Share current room"
const SHARE_SHORT := "Share room"
const SHARE_SCOPE := "All friends"
const SHARED := "Shared with friends"
const STOP_SHARING := "Stop sharing room"
const REDO_REQUESTED := "Redo requested"
const ASK_FOR_REDO := "Ask for redo"
const TURN_REQUESTS := "Turn requests"

## id: the action.
##   button: an action_buttons.gd id (its label, icon and look), or
##   text: the label of a plain card button, primary: its cream look.
##   icon: its icon on the wide room panel (a header action is icon only).
##   run: the screen's handler method, bind: its arguments; with_receipt: the
##   handler also takes the turn receipt the row was drawn for.
##   custom: the screen builds and wires this row itself (no run).
##   when: facts the screen must report true, in order ("!" negates).
##   short: its label on the wide waiting panel (custom rows only).
##   waiting: how the wide waiting panel places it. "primary" holds the
##   panel's one cream action while its button shows; "first_free" (custom
##   rows only) is cream when no row above holds it, else outlined;
##   "outlined" always is. The first two outlined rows share a line below the
##   others; any further one is full width.
const ACTIONS := {
	"copy_code": {"text": "Copy invitation code", "icon": preload("res://assets/ui/social/copy.svg"), "custom": true, "when": ["invited", "!joined"]},
	"share": {"text": SHARE, "short": SHARE_SHORT, "icon": preload("res://assets/ui/social/share-network.svg"), "custom": true, "waiting": "first_free", "when": ["share"]},
	"check_saved": {"button": "check_saved", "run": "_online_refresh", "waiting": "primary", "when": ["pending"]},
	"keep_held": {"text": PlayerCopy.RELAY_PREVIEW_D4FF2D8D4CDF, "run": "_keep_held_turn", "when": ["held"]},
	"notify": {"text": PlayerCopy.MAIN_C4B947AAAE59, "primary": true, "run": "_enable_turn_notifications", "waiting": "primary", "when": ["!pending", "notifications"]},
	"resume": {"button": "resume", "run": "_turn_tap", "bind": ["resume"], "when": ["draft"]},
	"record": {"button": "record", "run": "_turn_tap", "bind": ["record"], "when": []},
	"refresh": {"button": "refresh", "icon": preload("res://assets/ui/social/arrows-clockwise.svg"), "run": "_online_refresh", "when": ["online", "!pending"]},
	"replays": {"button": "replays", "run": "_play_replays", "when": ["online", "watchable"]},
	"local_replays": {"button": "replays", "run": "_show_local_replays", "when": ["solo", "watchable"]},
	"redo_answer": {"text": REDO_REQUESTED, "run": "_open_redo", "when": ["redo", "redo_accept"]},
	"redo": {"text": ASK_FOR_REDO, "run": "_open_redo", "when": ["redo", "!redo_accept"]},
	"solo_redo": {"text": PlayerCopy.SOLO_REDO_ACTION, "run": "_confirm_solo_redo", "when": ["solo_redo"]},
	"photo": {"text": "Photo for your last contribution", "run": "_offer_recent_photo", "with_receipt": true, "when": ["photo"]},
	"checkpoints": {"button": "retry", "run": "_choose_local_checkpoint", "when": ["solo"]},
	"new_room": {"text": "New room", "primary": true, "run": "_create_another_room", "when": ["online"]},
	"restart": {"text": "Restart chapter", "primary": true, "run": "_confirm_restart_chapter", "when": ["restart"]},
	"about": {"text": "About this chapter", "run": "_show_waiting_details", "when": ["about"]},
	"safety": {"text": "Report or block player", "run": "_open_safety", "when": ["safety"]},
	"room_options": {"text": "Room options", "custom": true, "waiting": "outlined", "when": ["options"]},
	"your_rooms": {"text": "Your rooms", "custom": true, "waiting": "first_free", "when": []},
	"back": {"button": "back", "run": "_leave", "when": []},
}

## state: {slot: action ids in screen order}. A state is drawn slot by slot:
##   invite: under the invitation status; turn: the main action list;
##   header: icons in the panel's title row; more: after the sync status line;
##   options: the Room options sheet.
## Panel states are the wide side panel; card states are the centred card
## (solo chapters, and online rooms on a narrow screen).
const LAYOUT := {
	"ready_panel": {
		"invite": ["copy_code", "share"],
		"turn": ["resume", "record", "redo_answer", "redo", "safety", "photo"],
		"header": ["refresh"],
	},
	"ready_card": {
		"invite": ["copy_code", "share"],
		"turn": ["resume", "record", "refresh", "local_replays", "restart", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
	"waiting_panel": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "notify", "redo_answer", "share", "room_options", "your_rooms"],
		"options": ["refresh", "replays", "redo", "photo", "about", "safety"],
	},
	"waiting_card": {
		"invite": ["copy_code"],
		"turn": ["check_saved", "keep_held", "notify", "redo_answer", "redo", "refresh", "share"],
		"more": ["replays", "safety", "photo", "back"],
	},
	"complete": {
		"turn": ["replays", "local_replays", "checkpoints", "new_room", "redo_answer", "redo", "solo_redo", "safety", "photo", "back"],
	},
}

## Cards outside the room panel (pause, review) add these rows when they apply.
const REDO_ACTIONS := ["redo_answer", "redo", "solo_redo"]

## The ids of one slot of one state that apply now. `fact(name, state)`
## answers a fact with a bool; facts are read in row order and only as far as
## needed.
static func shown(state: String, slot: String, fact: Callable) -> Array[String]:
	var ids: Array[String] = []
	for id: String in LAYOUT.get(state, {}).get(slot, []):
		if applies(id, fact, state): ids.append(id)
	return ids

static func applies(id: String, fact: Callable, state: String = "") -> bool:
	for name: String in ACTIONS[id].when:
		if name.begins_with("!") == bool(fact.call(name.trim_prefix("!"), state)): return false
	return true

static func label(id: String, fact: Callable = Callable()) -> String:
	var row: Dictionary = ACTIONS[id]
	if id == "redo" and fact.is_valid(): return redo_label(false, fact.call("my_turn", ""))
	return str(ActionButtons.DEFINITIONS[row.button].label) if row.has("button") else str(row.text)

## A redo request button's label, for the online room and the legacy room page.
static func redo_label(can_accept: bool, my_turn: bool) -> String:
	return REDO_REQUESTED if can_accept else ASK_FOR_REDO if my_turn else TURN_REQUESTS
