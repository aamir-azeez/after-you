extends RefCounted
## World kit: what else a goal waits for, beside its two pips (kit/pieces/
## goal.gd). A stage's goal may ask more than both pips standing at it (its
## goal_policy "when", core/journey/seven_mechanisms.gd predicate): an item
## carried or set down, a lever pulled (a lantern lit), a switch set, a light
## reaching its receiver, a pad held. Each such need gets a big token in a
## row on the plate's middle line at its front edge, clear of where the pips
## stand: a dim slate drum standing up through the plate's seam with the
## need's own icon on it, the drum lit while the need is met (and red while a
## pip waits on the plate without it, kit/pieces/goal.gd present_missing). So
## a pip at the goal sees what is still missing, with no words, at phone size.
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
## The token: its drum's radius and how far it stands over the plate, the
## gap between tokens' centres, how big its icon is drawn (the icons below
## are sized for a token ICON_BASE across; an item's own model keeps its
## size, low enough to step past), and how small an item's model stands on it.
const TOKEN := 0.1
const TOKEN_HEIGHT := 0.012
const GAP := 0.22
const ICON_BASE := 0.07
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

## How far from the goal's centre a row of `count` tokens reaches, at the
## front edge of a plate `plate_half` across (m; 0 for none): the goal's
## drawn radius (kit/pieces/goal.gd) covers it.
static func reach(plate_half: float, count: int) -> float:
	if count <= 0: return 0.0
	return Vector2(GAP * float(count - 1) * 0.5, plate_half).length() + TOKEN

## Builds a token per need of `stage`'s goal under `root` (the goal's root):
## the row centred on `front` (the floor it stands on), each drum standing
## `rise` up to the plate's top and TOKEN_HEIGHT over it; `item_style` names
## an item's style (Callable(id) -> String).
func build(stage: Dictionary, root: Node3D, front: Vector3, rise: float, item_style: Callable) -> void:
	_stage = stage
	_open = stage.get("pressure_pads", []).any(func(pad: Dictionary) -> bool: return str(pad.get("owner_slot", "")).is_empty())
	var list := terms(stage.get("goal_policy", {}).get("when", {}))
	for index in range(list.size()):
		var term: Dictionary = list[index]
		var at := front + Vector3((float(index) - float(list.size() - 1) * 0.5) * GAP, 0, 0)
		var disc := Parts.disc(TOKEN, rise + TOKEN_HEIGHT, SLATE, at + Vector3(0, (rise + TOKEN_HEIGHT) * 0.5, 0), root, -1.0, 16)
		disc.name = "GoalNeed"
		var holder := Node3D.new()
		holder.name = "GoalNeedIcon"
		holder.position = at + Vector3(0, rise + TOKEN_HEIGHT, 0)
		holder.scale = Vector3.ONE * (1.0 if icon(term) == "item" else TOKEN / ICON_BASE)
		root.add_child(holder)
		_icon(icon(term), term, Vector3.ZERO, holder, item_style)
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
			item.root.scale = Vector3.ONE * _item_scale(item.root, at.y)
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

## ITEM_SCALE, or smaller for an item a pip at the goal would stand in: a part
## both wider than the kit's small stand and rising past its step-on height
## over the goal's floor (kit/prop_rules.gd stands_in), such as a lens on its
## edge, shrinks until it is no wider than that stand. `floor_top` is how high
## the item's root stands over the goal's floor (m).
static func _item_scale(item: Node3D, floor_top: float) -> float:
	var rules: GDScript = load("res://presentation/kit/prop_rules.gd")
	var scale := ITEM_SCALE
	for mesh: Node in item.find_children("*", "MeshInstance3D", true, false):
		var shape: Mesh = (mesh as MeshInstance3D).mesh
		if shape == null: continue
		var placed := Transform3D.IDENTITY
		var node: Node = mesh
		while node != item:
			placed = (node as Node3D).transform * placed
			node = node.get_parent()
		var box: AABB = placed * shape.get_aabb()
		var width := maxf(box.size.x, box.size.z)
		if floor_top + box.end.y * ITEM_SCALE > float(rules.STEP_ON) and width * ITEM_SCALE > float(rules.SMALL_STAND):
			scale = minf(scale, float(rules.SMALL_STAND) * 0.95 / width)
	return scale
