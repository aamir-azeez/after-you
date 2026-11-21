extends SceneTree
## Soft contact shadows (presentation/kit/contact_shadows.gd): every piece
## style and every dressing kind gets one by default, sized from its own feet,
## unless it is ground itself, hangs or rides the water (each listed with why);
## a world bakes what stands still into the floor it stands on (soft, round,
## never doubled, grass worn round a base) and draws what moves in one
## MultiMesh that follows it and hides what is hidden, carried or afloat.
## Every chapter stage's world bakes them (test_world_looks checks it there).
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
const Cutaway = preload("res://presentation/kit/cutaway.gd")
const KeepsakeParts = preload("res://presentation/keepsakes/keepsake_parts.gd")
## How far past its own footprint (Props.extent()) a grown or tiny dressing
## prop's shade may reach, metres.
const STAMP_MARGIN := 0.1
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
	_check_dressing_stamps(holder)
	_check_unseen(holder)
	holder.free()
	_check_bake()
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

## Dressing that grows (PROP_SOFT) or is tiny (under TINY_HEIGHT): every
## stamp round, never square-edged, wearing no grass, and no shade past the
## prop's own footprint plus STAMP_MARGIN; a tiny one is one faint stamp with
## no sun shadow. A part that leans a little keeps its base's outline, never
## its whole box.
func _check_dressing_stamps(holder: Node3D) -> void:
	var tested := 0
	for kind: String in _prop_kinds():
		if ContactShadows.PROP_NONE.has(kind): continue
		var spec := {"kind": kind, "at": [37, 11]}
		if kind in Styles.LINE_KINDS: spec = {"kind": kind, "from": [-80, 0], "to": [80, 0]}
		var prop := Props.build(spec, holder, 0.0, false)
		if prop == null: continue
		var feet := ContactShadows.feet(prop)
		var tiny := feet.size() == 1 and float(feet[0][5]) < 1.0
		_check(ContactShadows.PROP_SOFT.has(kind) == (str(prop.get_meta(ContactShadows.LOOK_META)) == "soft"), "A %s is marked soft only when PROP_SOFT names it" % kind)
		if not tiny and not ContactShadows.PROP_SOFT.has(kind): continue
		tested += 1
		if tiny: _check((prop.get_meta(ContactShadows.CASTERS_META) as Array).is_empty() and is_equal_approx(float(feet[0][5]), ContactShadows.TINY_STRENGTH), "A tiny %s gets one faint shade and no sun shadow" % kind)
		var footprint: Rect2 = Props.extent(spec).rect
		var area := footprint.grow(1.0)
		for foot: Array in feet:
			_check(is_equal_approx(float(foot[3]), 1.0) and not bool(foot[6]), "A %s's shade is round and wears no grass: %s" % [kind, foot])
			var baked := ContactShadows.bake(area, [ContactShadows._ground_foot(foot, prop.transform)], [], true)
			var image: Image = baked.image
			var past := 0.0
			for j in range(image.get_height()):
				for i in range(image.get_width()):
					var shade := image.get_pixel(i, j)
					if shade.r == 0.0 and shade.g == 0.0: continue
					var at := area.position + (Vector2(i, j) + Vector2.ONE * 0.5) * ContactShadows.TEXEL
					past = maxf(past, Vector2(maxf(maxf(footprint.position.x - at.x, at.x - footprint.end.x), 0.0), maxf(maxf(footprint.position.y - at.y, at.y - footprint.end.y), 0.0)).length())
			_check(past <= STAMP_MARGIN, "A %s's shade reaches %.2f m past its footprint (at most %.2f)" % [kind, past, STAMP_MARGIN])
			# Not square-edged: at its footprint's corner the shade is lighter
			# than at the middle of its side (a stamp a few texels across is a
			# blur either way).
			var centre := ContactShadows._ground_foot(foot, prop.transform)[0] as Vector2
			var half := ContactShadows._ground_foot(foot, prop.transform)[1] as Vector2
			var pixel := func(point: Vector2) -> float: return image.get_pixelv(Vector2i(((point - area.position) / ContactShadows.TEXEL).floor())).r
			var side: float = pixel.call(centre + Vector2(half.x, 0))
			var corner: float = pixel.call(centre + half)
			_check(minf(half.x, half.y) < ContactShadows.TEXEL * 2.0 or corner < side, "A %s's shade is round, not a box: corner %.2f, side %.2f" % [kind, corner, side])
	_check(tested >= 4, "Grown and tiny dressing is checked: %d kinds" % tested)
	var leaning := _marked(holder)
	var straight := _marked(holder)
	var flower: Mesh = (Props.build({"kind": "flowers", "at": [0, 0]}, holder, 0.0, false).find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	for pair: Array in [[leaning, 0.08], [straight, 0.0]]:
		var part := MeshInstance3D.new()
		part.mesh = flower
		part.material_override = Primitives.shared_material(Color("6f9a64"))
		part.rotation = Vector3(pair[1], 0, 0)
		(pair[0] as Node3D).add_child(part)
	var lean_half: Vector2 = ContactShadows.feet(leaning)[0][1]
	var straight_half: Vector2 = ContactShadows.feet(straight)[0][1]
	_check(lean_half.distance_to(straight_half) < 0.02, "A part leaning a little keeps its base's outline, not its whole box: %s vs %s" % [lean_half, straight_half])

## Only what is drawn solid and stays is baked: a hidden part, a see-through
## one, an unearned keepsake's outline, a part drawn with no shadow and a
## part that moves or shows as its thing plays never count; a mesh the
## cutaway fades for now is still there.
func _check_unseen(holder: Node3D) -> void:
	var thing := _marked(holder)
	_box(thing, Vector3(0.2, 1.0, 0.2), Vector3(0, 0.5, 0))
	var hidden := _box(thing, Vector3(0.3, 1.2, 0.3), Vector3(1, 0.6, 0))
	hidden.visible = false
	var clear := Primitives.mesh_node(Primitives.cached_box(Vector3(0.3, 1.2, 0.3)), Primitives.shared_material(Color(0.8, 0.8, 0.8, 0.4)), Vector3(-1, 0.6, 0), thing)
	var faded := _box(thing, Vector3(0.3, 1.2, 0.3), Vector3(0, 0.6, 1))
	faded.transparency = 0.5
	var unlit := _box(thing, Vector3(0.3, 1.2, 0.3), Vector3(0, 0.6, -1))
	unlit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var veil := Primitives.mesh_node(Primitives.cached_box(Vector3(0.3, 1.2, 0.3)), KeepsakeParts.ghost(), Vector3(1, 0.6, 1), thing)
	var spinning := _box(thing, Vector3(0.3, 1.2, 0.3), Vector3(-1, 0.6, -1))
	ContactShadows.changes(spinning)
	_check(clear != null and veil != null, "The see-through parts are built")
	var feet := ContactShadows.feet(thing)
	var casters: Array = thing.get_meta(ContactShadows.CASTERS_META)
	_check(feet.size() == 1 and casters.size() == 1 and (feet[0][0] as Vector2).is_zero_approx(), "Only the solid post is baked, nothing hidden, see-through, unlit or changing: %d feet, %d casters" % [feet.size(), casters.size()])
	var under_cutaway := _marked(holder)
	var deck := _box(under_cutaway, Vector3(0.3, 1.2, 0.3), Vector3(0, 0.6, 0))
	Cutaway.fade_mesh(deck, true)
	_check(ContactShadows.feet(under_cutaway).size() == 1, "A part the cutaway fades for now still has its shadow")
	var source := FileAccess.get_file_as_string("res://presentation/home_keepsake_layer.gd")
	_check(source.contains("parts = builder.build(holder, state)") and source.contains("# Only an earned keepsake") and source.contains("ContactShadows.changes(part)"), "Home marks only earned keepsakes and leaves their moving parts out")

func _marked(holder: Node3D) -> Node3D:
	var node := Node3D.new()
	holder.add_child(node)
	ContactShadows.mark(node)
	return node

func _box(parent: Node3D, size: Vector3, at: Vector3) -> MeshInstance3D:
	return Primitives.mesh_node(Primitives.cached_box(size), Primitives.shared_material(Color("8a6b4e")), at, parent)

## Baking a floor: each foot its own soft shape, the darkest of overlapping
## feet (never their sum), round feet round, grass worn round a base, the
## space between two feet left clear, and drawn only over tiles that hold some.
func _check_bake() -> void:
	var rect := Rect2(0, 0, 4, 2)
	var round_foot := [Vector2(0.6, 0.6), Vector2(0.2, 0.2), 1.0, Vector2.RIGHT]
	var square_foot := [Vector2(1.4, 0.6), Vector2(0.2, 0.2), 0.0, Vector2.RIGHT]
	var baked := ContactShadows.bake(rect, [round_foot, square_foot], [], true)
	var image: Image = baked.image
	var at := func(x: float, z: float) -> Color: return image.get_pixel(int(x / ContactShadows.TEXEL), int(z / ContactShadows.TEXEL))
	_check(at.call(0.6, 0.6).r > 0.99 and at.call(1.4, 0.6).r > 0.99, "A foot is darkest where it stands")
	_check(at.call(0.6 + 0.19, 0.6 + 0.19).r < at.call(0.6 + 0.19, 0.6).r - 0.2, "A round foot's shade is round, not a box: %.2f by %.2f" % [at.call(0.79, 0.79).r, at.call(0.79, 0.6).r])
	_check(at.call(1.4 + 0.19, 0.6 + 0.19).r > 0.9, "A square foot's shade fills its corners")
	_check(at.call(1.0, 0.6).r == 0.0 and at.call(1.0, 0.6).g > 0.0, "Between two feet a little apart the grass is worn, not dark")
	_check(at.call(3.5, 1.5) == Color.BLACK, "Far from any foot the floor is untouched")
	var turned_foot := [Vector2(2.6, 1.1), Vector2(0.3, 0.12), 0.4, Vector2(0.6, 0.8)]
	var sun := [Vector2(3.0, 1.0), Vector2(0.8, 0.6), Vector2(0.4, 0.15), 0.1]
	var forward := ContactShadows.bake(rect, [round_foot, square_foot, turned_foot], [sun], true)
	_check((forward.image as Image).get_data() == (ContactShadows.bake(rect, [turned_foot, square_foot, round_foot], [sun], true).image as Image).get_data(), "A floor bakes the same in any order")
	var nudged := [turned_foot[0] + Vector2(1e-6, -1e-6), turned_foot[1], turned_foot[2], (turned_foot[3] as Vector2) + Vector2(1e-6, 0)]
	_check((forward.image as Image).get_data() == (ContactShadows.bake(rect, [round_foot, square_foot, nudged], [sun], true).image as Image).get_data(), "A last-bit difference in a foot changes no texel (inputs snap to a grid)")
	var twice := ContactShadows.bake(rect, [round_foot, round_foot], [], true)
	_check((twice.image as Image).get_data() == ContactShadows.bake(rect, [round_foot], [], true).image.get_data(), "Two feet in one place shade like one: no doubled layers")
	var bare := ContactShadows.bake(rect, [round_foot], [], false)
	_check((bare.image as Image).get_pixel(int(0.6 / ContactShadows.TEXEL) + 5, int(0.6 / ContactShadows.TEXEL)).g == 0.0, "A floor that is not grass does not wear")
	var tiles: Array[Rect2] = baked.tiles
	var covered := 0.0
	for tile: Rect2 in tiles: covered += tile.get_area()
	_check(covered < rect.get_area() * 0.5 and tiles.all(func(tile: Rect2) -> bool: return rect.encloses(tile)), "The overlay covers only tiles with shade, inside the floor: %.2f of %.2f m2" % [covered, rect.get_area()])
	_check(ContactShadows.bake(rect, [[Vector2(9, 9), Vector2(0.2, 0.2), 1.0, Vector2.RIGHT]], [], true).is_empty(), "A floor with nothing on it bakes nothing")
	var cast := ContactShadows.bake(rect, [], [[Vector2(2, 1), Vector2(1, 0), Vector2(0.5, 0.2), 0.1]], true)
	_check((cast.image as Image).get_pixel(int(2.4 / ContactShadows.TEXEL), int(1.0 / ContactShadows.TEXEL)).b > 0.9 and (cast.image as Image).get_pixel(int(2.4 / ContactShadows.TEXEL), int(1.0 / ContactShadows.TEXEL)).r == 0.0, "The sun's shadow has its own channel")
	var look := FileAccess.get_file_as_string(ContactShadows.SHADE_SHADER.resource_path)
	_check(look.contains("blend_mul") and look.contains("depth_draw_never") and look.contains("max(s.r"), "The floor's shade multiplies the floor, writes no depth and takes the darker of contact and sun")

## A world's layer: still things are baked into the floor they stand on, one
## overlay per floor; what moves, or stands on no floor, gets a live quad in
## one draw that follows it, fades as it is lifted and goes when it is hidden,
## carried or afloat. A still thing that moves is baked again where it settles.
func _check_layer() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var layer: Node3D = ContactShadows.new()
	world.add_child(layer)
	var lawn := ContactShadows.ground(world, Rect2(-3, -3, 6, 6), 0.0, true)
	var lawn_nodes := lawn.find_children("*", "", true, false).size()
	_check(ContactShadows.overlay_of(lawn) != null and ContactShadows.overlay_of(lawn).get_parent() == lawn and ContactShadows.overlay_of(lawn).mesh != null and ContactShadows.overlay_of(lawn).layers == 0, "A floor comes with its overlay, a whole mesh that draws nothing until it bakes")
	var lamp := Props.build({"kind": "lantern", "at": [100, 0]}, world, 0.0, false)
	var crate := Props.build({"kind": "crate", "at": [-100, 0]}, world, 0.0, false)
	var lever: RefCounted = Lever.build("plain", Vector3(0, 0, 1), world)
	var aloft: RefCounted = Lever.build("plain", Vector3(0, 0.6, 2), world)
	var item: RefCounted = CarriedItem.build("parcel", Vector3(0, 0, -1), world, {"id": "p"})
	# A jetty: one post on the lawn, one past its edge over the water.
	var jetty := _marked(world)
	_box(jetty, Vector3(0.1, 0.4, 0.1), Vector3(2.8, 0.2, -2.0))
	_box(jetty, Vector3(0.1, 0.4, 0.1), Vector3(3.6, 0.2, -2.0))
	await _settle(layer)
	_check(_index(layer, jetty) < 0 and jetty in layer.baked_roots().map(func(entry: Array) -> Node3D: return entry[0]), "A foot past the floor's edge gets no shadow; the one on it is baked")
	jetty.free()
	await _settle(layer)
	var baked: Array = layer.baked_roots().map(func(entry: Array) -> Node3D: return entry[0])
	_check(lamp in baked and crate in baked and lever.root in baked and baked.size() == 3, "Still things on the floor are baked into it: %s" % [baked])
	var overlays: Array = layer.overlays()
	_check(overlays.size() == 1 and overlays[0].ground == lawn and (overlays[0].overlay as Node).get_parent() == lawn, "One overlay for the floor, under its ground (so it moves and hides with it)")
	_check(lawn.find_children("*", "", true, false).size() == lawn_nodes and overlays[0].overlay == ContactShadows.overlay_of(lawn), "Baking fills the floor's own overlay and adds no node")
	var overlay: MeshInstance3D = overlays[0].overlay
	_check((overlay.material_override as ShaderMaterial).shader == ContactShadows.SHADE_SHADER and is_equal_approx(overlay.mesh.get_aabb().position.y, ContactShadows.SHADE_TOP) and overlay.layers != 0, "The overlay lies at the shadows' height in the floor's look, drawn")
	var image: Image = overlays[0].image
	var texel := func(of: Image, x: float, z: float) -> Color: return of.get_pixel(int((x + 3.0) / ContactShadows.TEXEL), int((z + 3.0) / ContactShadows.TEXEL))
	_check(texel.call(image, -1.0, 0.0).r > 0.9 and texel.call(image, 1.0, 0.0).r > 0.9, "The crate and the lamp shade the floor where they stand")
	var many: MultiMesh = (layer.get_node("Shadows") as MultiMeshInstance3D).multimesh
	var live_roots := {}
	for index in range(layer.shown()): live_roots[layer.shadow(index).root] = true
	_check(live_roots.keys() == [item.root, aloft.root] or live_roots.keys() == [aloft.root, item.root], "Only the item and the lever on no floor get live shadows: %s" % [live_roots.keys()])
	_check(many.instance_count == layer.shown(), "One quad per live foot")
	_check(layer.find_children("*", "MultiMeshInstance3D", true, false).size() == 1, "Live shadows draw in one MultiMesh")
	_check(is_equal_approx((layer.shadow(_index(layer, aloft.root)).transform as Transform3D).origin.y, 0.6 + ContactShadows.SHADE_TOP), "A live shadow lies on its spot's level")
	# A live thing is followed within a few frames, without gathering again.
	item.root.position.x = 2.0
	await _frames(ceili(2.0 / ContactShadows.POLL_PER_FRAME) + 3)
	_check(is_equal_approx((layer.shadow(_index(layer, item.root)).transform as Transform3D).origin.x, 2.0 + (ContactShadows.feet(item.root)[0][0] as Vector2).x), "A moved item's shadow follows it")
	item.root.position.y = ContactShadows.LIFT_FADE * 0.5
	await _frames(3)
	var drawn: Dictionary = layer.shadow(_index(layer, item.root))
	_check(is_equal_approx(float(drawn.strength), 0.5) and is_equal_approx((drawn.transform as Transform3D).origin.y, ContactShadows.SHADE_TOP), "A lifted thing's shadow stays on the ground, half faded: %.2f" % float(drawn.strength))
	item.root.position = Vector3(2, 0, -1)
	# A still thing moved is baked again where it settles.
	crate.position.x = -2.0
	await _frames(ContactShadows.HOT_FRAMES + 20)
	await _settle(layer)
	image = layer.overlays()[0].image
	_check(texel.call(image, -2.0, 0.0).r > 0.9 and texel.call(image, -1.0, 0.0).r == 0.0, "A still thing moved is baked again where it settled")
	# Hidden, carried, floating: gone; set down: back.
	lamp.visible = false
	await _settle(layer)
	_check(lamp not in layer.baked_roots().map(func(entry: Array) -> Node3D: return entry[0]), "A hidden prop is baked out")
	item.carry(world)
	await _frames(2)
	_check(_index(layer, item.root) < 0, "A carried item's shadow goes (the pip shows it)")
	item.rest(Vector3(0, 0, -1), world, true)
	await _frames(2)
	_check(_index(layer, item.root) < 0, "A floating item has none (the water shows it)")
	item.rest(Vector3(0, 0, -1), world, false)
	await _frames(2)
	_check(_index(layer, item.root) >= 0, "An item set down has its shadow again")
	layer.set_quality("low")
	_check(not bool((overlay.material_override as ShaderMaterial).get_shader_parameter("detail")), "Low drops the worn grass's detail")
	layer.set_quality("balanced")
	_check(bool((overlay.material_override as ShaderMaterial).get_shader_parameter("detail")), "Balanced keeps it")
	Cutaway.set_faded(world, true)
	_check(not overlay.visible, "A faded floor hides its shade")
	Cutaway.set_faded(world, false)
	_check(overlay.visible, "A floor shown again shows it")
	lawn.visible = false
	await _settle(layer)
	_check(layer.overlays().is_empty() and layer.baked_roots().is_empty() and overlay.mesh != null and overlay.layers == 0, "A hidden floor bakes nothing and its overlay stays whole, drawing nothing")
	world.free()

## Frames until the layer has baked everything waiting.
func _settle(layer: Node3D) -> void:
	await _frames(2)
	for frame in range(60):
		if layer.settled(): return
		await process_frame
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
