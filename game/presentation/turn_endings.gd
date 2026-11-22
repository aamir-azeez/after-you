extends RefCounted
## Turn endings that are not the usual review: a turn the rules ended early
## (journey tide rules: a spirit drowned, or fell off a stone its water left
## high; the pieces rules: a pip carrying something stepped onto a crossing
## needing both hands and dropped it), or under open turns the stage's last turn
## (its cap) over without the stage finished, which no pass can follow. Each
## kind is data here; the chapter
## screen shows any of them the same way (relay_preview.gd _show_ending_card,
## _show_ending_beat), so a future failure ending is one more row.
##   badge:  the spirit expression on the ending's badge (spirit_look.gd); a
##           look without it shows the spirit's usual face.
##   water:  the badge's spirit sits half under water.
##   rows:   the card's buttons, row by row: shared action ids
##           (action_buttons.gd), "redo" for the screen's redo actions
##           (Redo last turn, or a friend room's request) and "start_over"
##           for its Start over.
##           Its way home is the card's Home square, as on every card.
##   beat:   physics frames of the beat (badge and line over the dimmed world)
##           before the card; tapping skips it.
## Whether such a turn may be kept (a draft, a replay, an upload) is the
## rules' call (the simulation's keeps_draft()), not the card's.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const KINDS := {
	"drowned": {"badge": &"knocked_out", "water": true, "rows": [["try_again"], ["preview", "redo"]], "beat": 30},
	"fell": {"badge": &"dizzy", "water": true, "rows": [["try_again"], ["preview", "redo"]], "beat": 30},
	"dropped": {"badge": &"surprised", "water": false, "rows": [["try_again"], ["preview", "redo"]], "beat": 30},
	"last_turn": {"badge": &"sad", "water": false, "rows": [["try_again"], ["preview", "redo"], ["start_over"]], "beat": 30},
}
## Each spirit's colour on a badge, as the world draws them.
const SLOT_COLORS: Dictionary = preload("res://presentation/spirit_look.gd").SLOT_COLOR_NAMES

## The ending a snapshot shows, or {} for the usual review:
## {"kind", "slot" (whose spirit), "line" (the editable line), ...KINDS[kind]}.
## solo: the partner is the player's own memory (PlayerCopy solo wording).
## world: the world showing it, which names a dropped item's crossing
## (hands_crossing: ladder, rope ladder, wheel or rope bridge); without one
## it is a ladder.
static func of(snapshot: Dictionary, solo: bool, world: Object = null) -> Dictionary:
	var drowned: Dictionary = snapshot.get("drowned", {})
	if drowned.is_empty(): return _last_turn(snapshot)
	var kind := "dropped" if drowned.has("dropped") else "fell" if drowned.has("fell") else "drowned"
	var ending: Dictionary = KINDS[kind].duplicate(true)
	ending.kind = kind
	ending.slot = str(drowned.get("slot", ""))
	ending.color = SLOT_COLORS.get(ending.slot, "peach")
	ending.line = PlayerCopy.from_canonical(str(snapshot.get("commit_reason", "")), solo)
	if kind == "dropped":
		var route := str(drowned.get("route", ""))
		var crossing := str(world.call("hands_crossing", route)) if world != null and world.has_method("hands_crossing") else "ladder"
		ending.line = PlayerCopy.dropped_line(ending.slot == str(snapshot.get("active_slot", "")), solo, str(drowned.dropped), crossing)
	return ending

## The stage's last turn over with the stage not finished: no pass may follow
## it (the snapshot's must_finish, core/physical/runtime.gd), so the turn is
## played again or an earlier one is taken back. {} for any other turn.
static func _last_turn(snapshot: Dictionary) -> Dictionary:
	if not bool(snapshot.get("must_finish", false)) or not bool(snapshot.get("finished", false)) or bool(snapshot.get("complete", false)) or bool(snapshot.get("passed", false)): return {}
	var ending: Dictionary = KINDS.last_turn.duplicate(true)
	ending.kind = "last_turn"
	ending.slot = str(snapshot.get("active_slot", ""))
	ending.color = SLOT_COLORS.get(ending.slot, "peach")
	ending.line = PlayerCopy.OPEN_TURNS_OUT_OF_TURNS
	return ending

## The line split after its first sentence, for a two-tone title:
## ["Oh no, you drowned!", "Try again?"], or [line, ""].
static func line_parts(line: String) -> Array:
	for mark: String in ["! ", "? ", ". "]:
		var at := line.find(mark)
		if at >= 0 and at + 2 < line.length(): return [line.left(at + 1), line.substr(at + 2)]
	return [line, ""]
