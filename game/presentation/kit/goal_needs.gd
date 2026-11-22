extends RefCounted
## World kit: what else a goal waits for, beside its two pips (kit/pieces/
## goal.gd). A stage's goal may ask more than both pips standing at it (its
## goal_policy "when", core/journey/seven_mechanisms.gd predicate): an item
## carried or set down, a lever pulled (a lantern lit), a switch set, a light
## reaching its receiver, a pad held. Each such need gets a big token (about
## 40 cm across) on a sign over the goal's stand (above the bell's frame, the
## lantern's pole, the window's frame; a planter or crest gets a short post),
## leaning back to face the camera, clear of the plate and any pip: a dim slate
## drum with the need's own icon on it. It stays plain while the need is unmet
## and goes red, on the closing warning's beat, only while a pip stands on the
## plate (kit/pieces/goal.gd present_missing). A met need's drum turns cream
## with a tick in place of its icon. So a pip at the goal sees what is still
## missing, with no words, at phone size.
##
## Needs come from the definition alone: "all" is read as its parts, each a
## need; anything else ("any", "not", a leaf) is one need, met exactly when
## the rule says. Each kind of need has an icon (ICONS); a kind not listed
## gets DEFAULT_ICON. An item's icon is the item itself, in its style, fitted
## to the token (a seed, which only a world draws, a gold seed).
##
## Presentation only: it reads the snapshot with the rules' own predicate
## (pure, on the snapshot's mechanisms) and never feeds back. The sign hangs
## above walkable height, so it is no step-over obstacle and adds nothing to
## the goal's drawn footprint (kit/pieces/goal.gd drawn_radius).
const Parts = preload("res://presentation/kit/pieces/parts.gd")
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const CarriedItemKit = preload("res://presentation/kit/pieces/carried_item.gd")
const ViewFit = preload("res://presentation/kit/view_fit.gd")
## Need kind (the term's key) -> icon.
const ICONS := {"item_id": "item", "lever_id": "lamp", "signal_id": "lamp", "control_id": "dial", "pad_id": "ring"}
const DEFAULT_ICON := "stone"
## The token: its drum's radius and thickness, the gap between tokens'
## centres, how big its icon is drawn (the icons below are sized for a token
## ICON_BASE across), and how wide an item's model is fitted on it (m).
const TOKEN := 0.2
const TOKEN_HEIGHT := 0.03
const GAP := 0.5
const ICON_BASE := 0.07
const ITEM_FIT := 0.26
const SLATE := Color("6b7480")
const TICK := Color("3f8f5a")
## The sign's backing board past the tokens, and its thickness (m).
const BOARD_MARGIN := 0.06
const BOARD_THICK := 0.03
## The post under a sign that has no stand of its own: its radius.
const POST := 0.035

## Per need: {term, disc (the token that lights), icon, tick, met}.
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

## Builds the sign for each need of `stage`'s goal under `root` (the goal's
## root): its centre at `at` (root space), turned and leaned to face the
## camera (kit/view_fit.gd CAMERA_FROM), on a post down to the floor when
## `post` is set; `item_style` names an item's style (Callable(id) -> String).
func build(stage: Dictionary, root: Node3D, at: Vector3, post: bool, item_style: Callable) -> void:
	_stage = stage
	_open = stage.get("pressure_pads", []).any(func(pad: Dictionary) -> bool: return str(pad.get("owner_slot", "")).is_empty())
	var list := terms(stage.get("goal_policy", {}).get("when", {}))
	if list.is_empty(): return
	var facing := ViewFit.CAMERA_FROM.normalized()
	var sign := Node3D.new()
	sign.name = "GoalNeedSign"
	sign.position = at
	sign.rotation.y = atan2(facing.x, facing.z)
	root.add_child(sign)
	var board := Node3D.new()
	board.rotation.x = atan2(Vector2(facing.x, facing.z).length(), facing.y)
	sign.add_child(board)
	if post: Parts.cylinder(POST, at.y, Parts.TIMBER_DARK, Vector3(0, -at.y * 0.5, 0), sign)
	var wide := GAP * float(list.size() - 1) + TOKEN * 2.0 + BOARD_MARGIN * 2.0
	Parts.box(Vector3(wide, BOARD_THICK, TOKEN * 2.0 + BOARD_MARGIN * 2.0), Parts.TIMBER_DARK, Vector3(0, -BOARD_THICK * 0.5, 0), board)
	for index in range(list.size()):
		var term: Dictionary = list[index]
		var spot := Vector3((float(index) - float(list.size() - 1) * 0.5) * GAP, 0, 0)
		var disc := Parts.disc(TOKEN, TOKEN_HEIGHT, SLATE, spot + Vector3(0, TOKEN_HEIGHT * 0.5, 0), board, -1.0, 20)
		disc.name = "GoalNeed"
		var holder := Node3D.new()
		holder.name = "GoalNeedIcon"
		holder.position = spot + Vector3(0, TOKEN_HEIGHT, 0)
		holder.scale = Vector3.ONE * (TOKEN / ICON_BASE)
		board.add_child(holder)
		_icon(icon(term), term, Vector3.ZERO, holder, item_style)
		var tick := Node3D.new()
		tick.name = "GoalNeedTick"
		tick.position = spot + Vector3(0, TOKEN_HEIGHT, 0)
		tick.visible = false
		board.add_child(tick)
		var short := Parts.box(Vector3(0.1, 0.02, 0.04), TICK, Vector3(-0.06, 0.01, 0.045), tick)
		short.rotation.y = -PI / 4.0
		var long := Parts.box(Vector3(0.22, 0.02, 0.04), TICK, Vector3(0.05, 0.01, 0.0), tick)
		long.rotation.y = PI / 4.0
		needs.append({"term": term, "disc": disc, "icon": holder, "tick": tick, "met": false})

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
		(need.icon as Node3D).visible = not met
		(need.tick as Node3D).visible = met

## Whether every need is met as last shown.
func all_met() -> bool:
	return needs.all(func(need: Dictionary) -> bool: return bool(need.met))

## The parts that change (the tokens' discs, icons and ticks), kept whole by
## the static fold.
func moving_parts() -> Array[Node3D]:
	var parts: Array[Node3D] = []
	for need: Dictionary in needs:
		parts.append(need.disc)
		parts.append(need.icon)
		parts.append(need.tick)
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
			# Fitted to the token whatever the item's own size; the holder's
			# scale is the icons' (TOKEN / ICON_BASE), so undo it.
			item.root.scale = Vector3.ONE * (ITEM_FIT * ICON_BASE / TOKEN / maxf(_widest(item.root), 0.01))
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

## The widest side of `item`'s meshes (m, at scale 1).
static func _widest(item: Node3D) -> float:
	var widest := 0.0
	for mesh: Node in item.find_children("*", "MeshInstance3D", true, false):
		var shape: Mesh = (mesh as MeshInstance3D).mesh
		if shape == null: continue
		var placed := Transform3D.IDENTITY
		var node: Node = mesh
		while node != item:
			placed = (node as Node3D).transform * placed
			node = node.get_parent()
		var box: AABB = placed * shape.get_aabb()
		widest = maxf(widest, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	return widest
