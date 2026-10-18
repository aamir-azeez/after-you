extends RefCounted
## Words for the solo "Redo my previous turn" offer, built from a journey's
## redo_plan(). Text only: the chapter screen owns the flow, so any solo
## screen whose journey returns the same plan shape can reuse it.
const PlayerCopy = preload("res://presentation/player_copy.gd")

## The confirm card's title, body and confirm button for a plan, or {} when
## there is nothing to take back. The button repeats the title's verb.
static func confirm_copy(plan: Dictionary) -> Dictionary:
	var kind: Variant = plan.get("kind")
	if kind not in ["first_turn", "stage"]: return {}
	var stage_index := int(plan.get("stage_index", 0))
	var title := ""
	var confirm := ""
	var lines := PackedStringArray()
	if kind == "stage":
		title = PlayerCopy.SOLO_REDO_STAGE_TITLE % (stage_index + 1)
		confirm = PlayerCopy.SOLO_REDO_STAGE_CONFIRM % (stage_index + 1)
		lines.append(PlayerCopy.SOLO_REDO_STAGE_BODY)
	else:
		title = PlayerCopy.SOLO_REDO_FIRST_TURN_TITLE
		confirm = PlayerCopy.SOLO_REDO_FIRST_TURN_CONFIRM
		lines.append(PlayerCopy.SOLO_REDO_FIRST_TURN_BODY)
		if stage_index > 0: lines.append(PlayerCopy.SOLO_REDO_KEEPS_EARLIER)
	if plan.get("drops_draft", false): lines.append(PlayerCopy.SOLO_REDO_DROPS_DRAFT)
	return {"title": title, "body": " ".join(lines), "confirm": confirm}
