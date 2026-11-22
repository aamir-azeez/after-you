extends RefCounted
## World kit: what else a goal waits for, beside its two pips (kit/pieces/
## goal.gd). A stage's goal may ask more than both pips standing at it (its
## goal_policy "when", core/journey/seven_mechanisms.gd predicate): an item
## carried or set down, a lever pulled (a lantern lit), a switch set, a light
## reaching its receiver, a pad held. Each such need gets a small token in a
## row at the goal's front, between the pips' pads: a dim slate disc with the
## need's own icon on it, the disc lit while the need is met. So a pip at the
## goal sees what is still missing, with no words.
##
## Needs come from the definition alone: "all" is read as its parts, each a
## need; anything else ("any", "not", a leaf) is one need, met exactly when
## the rule says. Each kind of need has an icon (ICONS); a kind not listed
## gets DEFAULT_ICON. An item's icon is the item itself, in its style, small
## (a seed, which only a world draws, a small gold seed).
##
## Presentation only: it reads the snapshot with the rules' own predicate
## (pure, on the snapshot's mechanisms) and never feeds back.
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")
## Need kind (the term's key) -> icon.
const ICONS := {"item_id": "item", "lever_id": "lamp", "signal_id": "lamp", "control_id": "dial", "pad_id": "ring"}
const DEFAULT_ICON := "stone"
## The token: its disc's radius and height, the gap between tokens, how far
## in front of the goal's centre the row stands (a share of its radius), and
## how small an item's own model stands on it.
const TOKEN := 0.07
const TOKEN_HEIGHT := 0.02
const GAP := 0.17
const FRONT := 0.6
const ITEM_SCALE := 0.6
const SLATE := Color("6b7480")

## Per need: {term, disc (the token that lights), met}.
var needs: Array[Dictionary] = []
var _stage: Dictionary = {}
var _open := false

## The needs of `when` (a goal_policy "when"), in order.
static func terms(when: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if when.is_empty(): return found
	if when.has("all"):
		for part: Variant in when.all:
			if part is Dictionary: found.append_array(terms(part))
		return found
	found.append(when)
	return found

## The icon a need shows.
static func icon(term: Dictionary) -> String:
	for key: String in ICONS:
		if term.has(key): return ICONS[key]
	return DEFAULT_ICON

## Builds a token per need of `stage`'s goal under `root` (the goal's root,
## `radius_m` across, its disc's top at `top`); `item_style` names an item's
## style (Callable(id) -> String).
func build(stage: Dictionary, root: Node3D, radius_m: float, top: float, item_style: Callable) -> void:
	_stage = stage
	_open = stage.get("pressure_pads", []).any(func(pad: Dictionary) -> bool: return str(pad.get("owner_slot", "")).is_empty())
	var list := terms(stage.get("goal_policy", {}).get("when", {}))
	for index in range(list.size()):
		var term: Dictionary = list[index]
		var at := Vector3((float(index) - float(list.size() - 1) * 0.5) * GAP, top, radius_m * FRONT)
		var disc := Parts.disc(TOKEN, TOKEN_HEIGHT, SLATE, at + Vector3(0, TOKEN_HEIGHT * 0.5, 0), root, -1.0, 16)
		disc.name = "GoalNeed"
		_icon(icon(term), term, at + Vector3(0, TOKEN_HEIGHT, 0), root, item_style)
		needs.append({"term": term, "disc": disc, "met": false})

## Lights each need's token while `state` meets it; nothing when unchanged.
func present(state: Dictionary) -> void:
	if needs.is_empty() or not state.get("mechanisms") is Dictionary: return
	var players: Dictionary = state.get("players", {})
	var signals: Dictionary = state.get("optics", {}).get("signals", {})
	for need: Dictionary in needs:
		var met := Seven.predicate(need.term, _stage, players, state.mechanisms, signals, _open)
		if met == bool(need.met): continue
		need.met = met
		Parts.glow(need.disc, Parts.LIGHT, 1.0 if met else 0.0)

## Whether every need is met as last shown.
func all_met() -> bool:
	return needs.all(func(need: Dictionary) -> bool: return bool(need.met))

## The parts that change (the tokens' discs), kept whole by the static fold.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for need: Dictionary in needs: parts.append(need.disc)
	return parts

func _icon(kind: String, term: Dictionary, at: Vector3, root: Node3D, item_style: Callable) -> void:
	match kind:
		"item":
			var id := str(term.item_id)
			var look := str(item_style.call(id)) if item_style.is_valid() else ""
			if look == "seed":
				Parts.sphere(0.035, Parts.GOLD, at + Vector3(0, 0.035, 0), root)
				return
			var item: RefCounted = CarriedItemKit.build(look, at, root, {"id": "need-" + id})
			item.root.scale = Vector3.ONE * ITEM_SCALE
		"lamp":
			Parts.box(Vector3(0.02, 0.06, 0.02), Parts.TIMBER_DARK, at + Vector3(0, 0.03, 0), root)
			Parts.sphere(0.035, Parts.LIGHT, at + Vector3(0, 0.08, 0), root)
		"dial":
			Parts.disc(0.045, 0.015, Parts.BRASS, at + Vector3(0, 0.0075, 0), root)
			Parts.box(Vector3(0.012, 0.006, 0.04), Parts.CREAM, at + Vector3(0, 0.018, -0.012), root)
		"ring":
			Parts.torus(0.04, 0.008, Parts.CREAM, at + Vector3(0, 0.008, 0), root)
		_:
			Parts.disc(0.03, 0.03, Parts.CREAM, at + Vector3(0, 0.015, 0), root, 0.022, 6)
