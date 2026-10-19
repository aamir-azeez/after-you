extends RefCounted
## Turn endings that are not the usual review: a turn the rules ended early
## (journey tide rules: a spirit drowned). Each kind is data here; the chapter
## screen shows any of them the same way (relay_preview.gd _show_ending_card,
## _show_ending_beat), so a future failure ending is one more row.
##   badge:  the spirit expression on the ending's badge (spirit_look.gd); a
##           look without it shows the spirit's usual face.
##   water:  the badge's spirit sits half under water.
##   rows:   the card's buttons, row by row: shared action ids
##           (action_buttons.gd), and "redo" for the screen's redo actions.
##   beat:   physics frames of the beat (badge and line over the dimmed world)
##           before the card; tapping skips it.
## Whether such a turn may be kept (a draft, a replay, an upload) is the
## rules' call (the simulation's keeps_draft()), not the card's.
const PlayerCopy = preload("res://presentation/player_copy.gd")
const KINDS := {
	"drowned": {"badge": &"knocked_out", "water": true, "rows": [["try_again"], ["preview", "redo"], ["leave_draft"]], "beat": 30},
}
## Each spirit's colour on a badge, as the world draws them.
const SLOT_COLORS := {"p0": "peach", "p1": "mint"}

## The ending a snapshot shows, or {} for the usual review:
## {"kind", "slot" (whose spirit), "line" (the editable line), ...KINDS[kind]}.
## solo: the partner is the player's own memory (PlayerCopy solo wording).
static func of(snapshot: Dictionary, solo: bool) -> Dictionary:
	var drowned: Dictionary = snapshot.get("drowned", {})
	if drowned.is_empty(): return {}
	var ending: Dictionary = KINDS.drowned.duplicate(true)
	ending.kind = "drowned"
	ending.slot = str(drowned.get("slot", ""))
	ending.color = SLOT_COLORS.get(ending.slot, "peach")
	ending.line = PlayerCopy.from_canonical(str(snapshot.get("commit_reason", "")), solo)
	return ending

## The line split after its first sentence, for a two-tone title:
## ["Oh no, you drowned!", "Try again?"], or [line, ""].
static func line_parts(line: String) -> Array:
	for mark: String in ["! ", "? ", ". "]:
		var at := line.find(mark)
		if at >= 0 and at + 2 < line.length(): return [line.left(at + 1), line.substr(at + 2)]
	return [line, ""]
