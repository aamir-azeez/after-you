extends SceneTree
## Soft contact shadows (presentation/kit/contact_shadows.gd): every piece
## style and every dressing kind gets one by default, sized from its own feet,
## unless it is ground itself, hangs or rides the water (each listed with why);
## a world draws them all in one MultiMesh that follows what moves, hides what
## is hidden, carried or afloat, and keeps only the pieces' on Low. Every
## chapter stage's world draws them (test_world_looks counts them there).
const ContactShadows = preload("res://presentation/kit/contact_shadows.gd")
const Props = preload("res://presentation/kit/props.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Lever = preload("res://presentation/kit/pieces/lever.gd")
const Selector = preload("res://presentation/kit/pieces/selector.gd")
const Pad = preload("res://presentation/kit/pieces/pad.gd")
const Goal = preload("res://presentation/kit/pieces/goal.gd")
const Pulley = preload("res://presentation/kit/pieces/pulley.gd")
const Lift = preload("res://presentation/kit/pieces/lift.gd")
const CarriedItem = preload("res://presentation/kit/pieces/carried_item.gd")
const Socket = preload("res://presentation/kit/pieces/socket.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const AT := Vector3(1, 0.5, 2)
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	_check_props(holder)
	_check_pieces(holder)
	_check_feet(holder)
	holder.free()
	await _check_layer()
	_check_pip()
	print("CONTACT SHADOWS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The kinds kit/props.gd build() makes, read from its match.
func _prop_kinds() -> Array[String]:
	var source := FileAccess.get_file_as_string("res://presentation/kit/props.gd")
	var body := source.substr(source.find("static func build("))
	body = body.substr(0, body.find("\n\t\t_:"))
	var kinds: Array[String] = []
	var pattern := RegEx.create_from_string("\\n\\t\\t\"([a-z_]+)\":")
	for found: RegExMatch in pattern.search_all(body): kinds.append(found.get_string(1))
	return kinds

## Every dressing kind casts one standing on its own base, sized within its
## extent, unless PROP_NONE says why not; a prop set below its floor (in the
## marsh) or hung on a wall gets none.
func _check_props(holder: Node3D) -> void:
	var kinds := _prop_kinds()
	_check(kinds.size() > 40 and "tree" in kinds and "lamp_post" in kinds, "The dressing kinds are read from props.gd: %d" % kinds.size())
	for kind: String in ContactShadows.PROP_NONE: _check(kind in kinds, "PROP_NONE names %s, which props.gd no longer builds: delete it" % kind)
	for kind: String in kinds:
		if ContactShadows.PROP_NONE.has(kind):
			var bare := Node3D.new()
			holder.add_child(bare)
			ContactShadows.prop(bare, {"kind": kind, "at": [0, 0]})
			_check(not bare.is_in_group(ContactShadows.GROUP), "A %s gets no contact shadow" % kind)
			continue
		var spec := {"kind": kind, "at": [0, 0]}
		if kind in Styles.LINE_KINDS: spec = {"kind": kind, "from": [-80, 0], "to": [80, 0]}
		var prop := Props.build(spec, holder, 0.0, false)
		_check(prop != null and prop.is_in_group(ContactShadows.GROUP), "A %s is marked for a contact shadow" % kind)
		if prop == null: continue
		var feet := ContactShadows.feet(prop)
		_check(not feet.is_empty(), "A %s has feet" % kind)
		var reach := (Props.extent(spec).rect as Rect2).grow(0.3)
		for foot: Array in feet:
			var rect := Rect2((foot[0] as Vector2) - (foot[1] as Vector2), (foot[1] as Vector2) * 2.0)
			_check(reach.encloses(rect) and float(foot[2]) >= 0.0 and float(foot[2]) <= ContactShadows.GROUND_REACH, "A %s's shadow lies under it, on its ground: %s in %s at %.3f" % [kind, rect, reach, float(foot[2])])
	var marsh := Props.build({"kind": "bush", "at": [0, 0], "y": -10}, holder, 0.0, false)
	var hung := Props.build({"kind": "lantern", "at": [0, 0], "wall": true}, holder, 0.0, false)
	_check(not marsh.is_in_group(ContactShadows.GROUP) and not hung.is_in_group(ContactShadows.GROUP), "A prop set below its floor or hung on a wall gets none")
	# A tree stands on its trunk, not under its crown.
	var tree := Props.build({"kind": "tree", "at": [0, 0]}, holder, 0.0, false)
	var trunk: Vector2 = ContactShadows.feet(tree)[0][1]
	_check(trunk.x < 0.2 and trunk.y < 0.2, "A tree's shadow is its trunk's: %s" % trunk)

## Every piece style is marked through piece.gd _root(), stands on its spot's
## level and leaves out what moves; a lift's deck, a raft and a crossing are
## ground or ride the water and get none.
func _check_pieces(holder: Node3D) -> void:
	var built: Array = []
	for style: String in Styles.SLOTS.lever: built.append(["lever " + style, Lever.build(style, AT, holder, {"owner": "p1"})])
	for style: String in Styles.SLOTS.selector: built.append(["selector " + style, Selector.build(style, AT, holder, {"owner": "p0", "values": ["off", "rose", "moss"], "marks": [0, 1, 2], "id": "s"})])
	for style: String in Styles.SLOTS.pad: built.append(["pad " + style, Pad.build(style, AT, 0.32, holder, {"owner": "p0", "id": "step"})])
	for style: String in Styles.SLOTS.goal: built.append(["goal " + style, Goal.build(style, AT, 0.28, holder)])
	for style: String in Styles.SLOTS.pulley: built.append(["pulley " + style, Pulley.build(style, AT, holder)])
	for style: String in ["parcel", "pipsport"]: built.append(["item " + style, CarriedItem.build(style, AT, holder, {"id": style})])
	for entry: Array in built:
		var piece: RefCounted = entry[1]
		if entry[0] == "pad stand_spot":
			_check(not piece.root.is_in_group(ContactShadows.GROUP), "A stand spot is a mark on the floor: no shadow")
			continue
		_check(piece.root.is_in_group(ContactShadows.GROUP), "The %s is marked for a contact shadow" % entry[0])
		var kept := {}
		for part: Node3D in piece.moving_parts():
			if part != piece.root: kept[part.get_instance_id()] = true
		var feet := ContactShadows.feet(piece.root, kept)
		_check(not feet.is_empty(), "The %s has feet" % entry[0])
		for foot: Array in feet: _check(float(foot[2]) <= ContactShadows.GROUND_REACH and (foot[1] as Vector2).x < 1.0 and (foot[1] as Vector2).y < 1.0, "The %s's shadow lies at its foot: %s" % [entry[0], foot])
	for style: String in Styles.SLOTS.lift: _check(not Lift.build(style, Rect2(-1.0, -0.9, 2.0, 1.8), 0.0, 1.6, holder, {"drive": Vector3(-3.0, 0, -1.3)}).root.is_in_group(ContactShadows.GROUP), "A %s lift's deck is a floor: no shadow" % style)
	var nest := Node3D.new()
	holder.add_child(nest)
	Socket.relay(nest)
	_check(nest.is_in_group(ContactShadows.GROUP) and not ContactShadows.feet(nest).is_empty(), "A relay nest has a shadow")

## Feet: the parts that reach the lowest point, each its own shadow; a thing
## hung above its origin has none; parts the fold keeps (they move) never count.
func _check_feet(holder: Node3D) -> void:
	var gate := _marked(holder)
	_box(gate, Vector3(0.1, 1.0, 0.1), Vector3(-0.6, 0.5, 0))
	_box(gate, Vector3(0.1, 1.0, 0.1), Vector3(0.6, 0.5, 0))
	_box(gate, Vector3(1.3, 0.1, 0.1), Vector3(0, 1.05, 0))
	var feet := ContactShadows.feet(gate)
	_check(feet.size() == 2 and (feet[0][1] as Vector2).is_equal_approx(Vector2(0.05, 0.05)), "Two posts make two small shadows, not one under the beam: %s" % [feet])
	var hung := _marked(holder)
	_box(hung, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.6, 0))
	_check(ContactShadows.feet(hung).is_empty(), "A thing hung over its spot has no shadow")
	var lever := _marked(holder)
	_box(lever, Vector3(0.3, 0.1, 0.2), Vector3(0, 0.05, 0))
	var handle := _box(lever, Vector3(0.8, 0.05, 0.05), Vector3(0.5, 0.04, 0))
	feet = ContactShadows.feet(lever, {handle.get_instance_id(): true})
	_check(feet.size() == 1 and (feet[0][1] as Vector2).is_equal_approx(Vector2(0.15, 0.1)), "A kept moving part is left out of the feet: %s" % [feet])
	var sunk := _marked(holder)
	_box(sunk, Vector3(0.1, 1.0, 0.1), Vector3(0, 0.2, 0))
	_check(is_zero_approx(float(ContactShadows.feet(sunk)[0][2])), "A post sunk into the floor casts at the floor's level")

func _marked(holder: Node3D) -> Node3D:
	var node := Node3D.new()
	holder.add_child(node)
	ContactShadows.mark(node)
	return node

func _box(parent: Node3D, size: Vector3, at: Vector3) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_box(size), Primitives.shared_material(Color("8a6b4e")), at, parent)

## A world's layer: one draw for every shadow; it follows a move, drops a
## hidden, carried or floating thing, fades one lifted off its rest, and
## keeps only the pieces' on Low.
func _check_layer() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var layer: Node3D = ContactShadows.new()
	world.add_child(layer)
	var lamp := Props.build({"kind": "lantern", "at": [100, 0]}, world, 0.0, false)
	var crate := Props.build({"kind": "crate", "at": [-100, 0]}, world, 0.0, false)
	var lever: RefCounted = Lever.build("plain", Vector3(0, 0.2, 1), world)
	var item: RefCounted = CarriedItem.build("parcel", Vector3(0, 0, -1), world, {"id": "p"})
	await _frames(2)
	var many: MultiMesh = (layer.get_node("Shadows") as MultiMeshInstance3D).multimesh
	_check(layer.find_children("*", "GeometryInstance3D", true, false).size() == 1 and many.instance_count == 4 and layer.shown() == 4, "Four shadows in one draw: %d" % many.instance_count)
	_check(not (layer.get_node("Shadows") as GeometryInstance3D).material_override.shader.code.contains("depth_draw_always"), "Shadows write no depth")
	var lever_index := _index(layer, lever.root)
	_check(lever_index >= 0 and lever_index < 2 and _index(layer, item.root) < 2, "The pieces' shadows come first")
	_check(is_equal_approx((layer.shadow(lever_index).transform as Transform3D).origin.y, 0.2 + ContactShadows.LIFT), "A piece's shadow lies on its spot's level")
	# Moved: followed within a few frames, without gathering again.
	lever.root.position.x = 3.0
	await _frames(ceili(4.0 / ContactShadows.POLL_PER_FRAME) + 2)
	_check(is_equal_approx((layer.shadow(_index(layer, lever.root)).transform as Transform3D).origin.x, 3.0 + (ContactShadows.feet(lever.root)[0][0] as Vector2).x), "A moved piece's shadow follows it")
	# Lifted off its rest: it stays on the ground and fades.
	crate.position.y = ContactShadows.LIFT_FADE * 0.5
	await _frames(3)
	var lifted := _index(layer, crate)
	var drawn: Dictionary = layer.shadow(lifted)
	_check(is_equal_approx(float(drawn.strength), 0.5) and is_equal_approx((drawn.transform as Transform3D).origin.y, ContactShadows.LIFT), "A lifted thing's shadow stays on the ground, half faded: %.2f" % float(drawn.strength))
	# Hidden, carried, floating: gone; set down: back.
	lamp.visible = false
	await _frames(2)
	_check(many.instance_count == 3, "A hidden prop's shadow goes")
	item.carry(world)
	await _frames(2)
	_check(many.instance_count == 2, "A carried item's shadow goes (the pip shows it)")
	item.rest(Vector3(0, 0, -1), world, true)
	await _frames(2)
	_check(many.instance_count == 2, "A floating item has none (the water shows it)")
	item.rest(Vector3(0, 0, -1), world, false)
	await _frames(2)
	_check(many.instance_count == 3, "An item set down has its shadow again")
	lamp.visible = true
	await _frames(2)
	layer.set_quality("low")
	_check(many.visible_instance_count == 2 and layer.shown() == 2, "Low keeps the pieces' shadows only")
	layer.set_quality("balanced")
	_check(many.visible_instance_count == -1 and layer.shown() == 4, "Balanced shows them all")
	crate.free()
	await _frames(2)
	_check(many.instance_count == 3, "A freed prop's shadow goes")
	world.free()


## process_frame comes before the nodes' _process: a change shows a frame later.
func _frames(count: int) -> void:
	for frame in range(count): await process_frame

## The first shadow drawn under node (the layer keeps what it drew: a
## headless run keeps no MultiMesh instance data).
func _index(layer: Node3D, node: Node3D) -> int:
	var found: Array[int] = layer.shadows_of(node)
	return found[0] if not found.is_empty() else -1

## A pip's shadow is the same look: the shared shader, sized SHADOW_RADIUS.
func _check_pip() -> void:
	var pip: Node3D = SpiritVisual.new()
	root.add_child(pip)
	var shadow: MeshInstance3D = pip.ground_shadow
	_check((shadow.material_override as ShaderMaterial).shader == ContactShadows.SHADER and is_equal_approx((shadow.mesh as PlaneMesh).size.x, SpiritVisual.SHADOW_RADIUS * 2.0), "A pip's shadow is the contact shadows' look, as wide as before")
	pip.free()
