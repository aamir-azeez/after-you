extends RefCounted
## World kit: pair tags, the small lettered tiles that tie a control (a pad, a
## lever, a selector, a receiver) to each gate it works. The pairs come from
## the stage's own control-to-gate wiring (its gates' pad_id, lever_id,
## second_lever_id, ball_pad_id and `when` references): each wired control
## gets the next letter A to J and a muted colour, shown on a tile at every
## gate it works (the outputs). An input a pip walks up to and works (a lever,
## a selector, a pressure pad: PROMPTED) has no floor tile: its letter shows in
## the play screen's action pop-up while the live pip is at it (prompt(), drawn
## by kit/pair_chip.gd, lit while the control is on). A ball pad keeps a tile
## beside it, as no pop-up carries its letter. A light receiver is a result,
## not an input: its letter is on a plaque on its own lamp post (no floor tile
## beside it), which lights only while one of its gates stands open, and its
## inputs are the mirrors on the paths that light it (_light_inputs), which
## carry its letter in the pop-up and show its pair near. A gate several controls work
## shows their tiles side by side in one short row; a control whose tile and
## gate tile would touch shows it once, and every row is placed on its own
## floor clear of the controls, the ownership marks, the decks and other rows,
## by the gate's entrance or, without room there, by its far end. A world overrides with skip() (a control or gate it shows some other
## way) and tag() (a tile on a sign it builds itself); it supplies the floor
## point of a control (_pair_control_anchor), of a gate's crossing's ends,
## the entrance first (_pair_gate_anchors), a receiver's lamp post
## (_pair_receiver_post: {top, radius}) and anything else of its own a tile keeps clear of
## (_pair_keep_clear: discs {centre, radius} or {rect}, with an optional y).
##
## States, from the snapshot alone and per tile: faint (a soft wash of the
## colour and a whisper of the letter), near (full colour, a lighter face, a
## solid letter) while either spirit stands within NEAR_CM of one of the
## pair's inputs on its floor, and lit (a bright glowing fill, its ink letter,
## and a pool of warm light around the tile): a lever's or pad's tiles while
## it is on or held; a selector's or receiver's tile at a gate only while that
## gate stands open at a value it asks of the selector, so a selector lights
## the one gate end its value opens; a receiver's plaque while any of its
## gates is open. On a plaque's metal the faint state shows a little more
## (PLAQUE_FAINT_ALPHA), so its letter still reads. The world
## hands the stage over with prepare() and the tiles are laid out when first
## shown or read, after every world has built its own scenery.
## Past ten pairs the letters start again with a band down the tile's edge
## (the left for K to T, both edges for the next ten), the colours repeating.
##
## Look: a rounded letter (the game's Fredoka) on the pair's colour, set in a
## small token whose frame follows the level's "tag" prop slot (a dressing's
## "tag", content/dressing/prop_styles.gd): a painted tile with a raised cream
## border, a little wooden plaque or a stone tile. Only the frame changes; the
## letter and the colour are the same in every style.
##
## Presentation only: built from the hashed stage and fed the snapshot;
## nothing here feeds the simulation, a recording or a checkpoint, so a replay
## shows what play showed. Cost: one mesh and one material per stage (a sign
## tile adds one small mesh; plaques share a second material, each a small
## mesh and four shared-material parts); present() works out the states, a few distance
## checks, and sets the material only when they change. The mirrors that light
## a receiver are traced once per stage, every way its mirrors can turn. The letter meshes, the
## pop-up's font and the shader are made once a session and let go through
## SessionRelease. The pop-up chip redraws only when its letter or state changes.
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
## Finding a clear spot on the floor, shared with the ownership marks.
const FloorSpots = preload("res://presentation/kit/floor_spots.gd")
## The game's own light rule, to find the mirrors that light a receiver.
const BeamField = preload("res://core/beam_field.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
## What a floor draws on its walking surface, which a tile lies over.
const Surfaces = preload("res://presentation/kit/surfaces.gd")
## The camera's angle, which a plaque faces.
const ViewFit = preload("res://presentation/kit/view_fit.gd")
const SHADER := preload("res://presentation/kit/pair_tags.gdshader")
## A tile is TAG across; tiles keep GAP from each other and from what they avoid.
const TAG := 0.28
const GAP := 0.05
## Tags whose places are closer than this (same floor) join one row.
const CLUSTER := 0.34
## Every layer (rim, face, bands, letter) lies this far over the floor: over
## everything a floor draws on its walking surface (its seams, planks and
## trims, Surfaces.RELIEF_TOP) by more than the depth buffer tells apart, and
## under a spirit's ground shadow (24 mm). The layers write no depth and draw
## in order, so they share the height.
const LIFT := Surfaces.RELIEF_TOP + 0.004
## The token: its coloured face is FACE of the tile across, a rounded square
## set a little up in its frame, whose darker edge shows EDGE below it so the
## frame looks raised. The letter is LETTER_SHARE of the face tall.
const FACE := 0.72
const FACE_ROUND := 0.16
const FACE_UP := 0.006
const EDGE := 0.007
const LETTER_SHARE := 0.58
const LETTER_HEIGHT := TAG * FACE * LETTER_SHARE
## The game's rounded UI letter, made flat once per letter.
const FONT := preload("res://assets/fonts/fredoka.ttf")
## Frames by the tag slot's style (prop_styles.gd SLOTS.tag): its colour and
## outline (a rounded square of `round` of the tile, or the chipped stone);
## the plaque adds two plank lines and two nail heads.
const FRAMES := {
	&"painted_tile": {"colour": Color("f6efd8"), "round": 0.24},
	&"wooden_plaque": {"colour": Color("b0845c"), "round": 0.075, "planks": true},
	&"stone_tile": {"colour": Color("c4beb2"), "chipped": true},
}
const DEFAULT_FRAME := &"painted_tile"
## A chipped stone outline, as shares of the tile from its centre, clockwise from above.
const CHIPPED := [Vector2(-0.442, -0.467), Vector2(0.392, -0.475), Vector2(0.475, -0.392), Vector2(0.467, 0.408), Vector2(0.375, 0.475), Vector2(-0.408, 0.467), Vector2(-0.475, 0.375), Vector2(-0.467, -0.408)]
const BAND := 0.012
const LETTERS := "ABCDEFGHIJ"
## Ten muted colours, each at least 20 (CIE76) from the others and from the
## owners' gold and teal (tests/test_pair_tags.gd measures it).
const PALETTE := [Color("c8806a"), Color("8fa87a"), Color("6f8fb0"), Color("c9a443"), Color("9c7aa3"), Color("4f8a8c"), Color("d99fac"), Color("7a7438"), Color("8a6a52"), Color("c2b6e6")]
const INK := Color("2f3534")
## The three states' look: every number the shader (pair_tags.gdshader) uses,
## checked apart by tests/test_pair_tags.gd. Faint: alphas per layer (rim,
## face, letter). Near: the tile at full strength, its face NEAR_LIGHTEN toward
## PALE, its letter solid ink. Lit: the fill LIT_LIGHTEN toward WARM and
## glowing at LIT_GLOW, the letter still ink, and a pool of GLOW light HALO
## times the tile across under it, GLOW_ALPHA strong at its centre. The pool
## stops half way to any other tile on its floor (glow_reach), so a glow never
## lies under a neighbour and an unlit tile beside a lit one stays unlit.
const FAINT_ALPHA := Vector3(0.18, 0.2, 0.14)
const NEAR_LIGHTEN := 0.1
const PALE := Color("fff8e0")
const LIT_LIGHTEN := 0.45
const LIT_GLOW := 0.5
const WARM := Color("ffdc94")
const GLOW := Color("ffe696")
const HALO := 3.6
const GLOW_ALPHA := 0.9
## Tiles this near in height share a floor for the pool's reach.
const GLOW_FLOOR := 0.3
## A receiver's plaque: a metal plate on a short arm, clamped to its lamp post
## PLAQUE_UP over its floor (on a shorter post PLAQUE_BELOW_TOP under its lamp
## head, never under PLAQUE_LOW), turned to face the camera. Its tile is
## PLAQUE_SCALE times a floor tile, so its letter reads at phone size, on a
## plate PLAQUE_MARGIN of it across with a darker rim and clamp. Faint, its
## layers (rim, face, letter) show PLAQUE_FAINT_ALPHA strong over the metal.
const PLAQUE_UP := 1.1
const PLAQUE_BELOW_TOP := 0.45
const PLAQUE_LOW := 0.3
const PLAQUE_SCALE := 1.45
const PLAQUE_MARGIN := 1.12
const PLAQUE_METAL := Color("697a88")
const PLAQUE_FAINT_ALPHA := Vector3(0.34, 0.38, 0.55)
## The shader's uniforms, by name (pair_tags.gdshader).
const LOOK := {&"faint_alpha": FAINT_ALPHA, &"near_lighten": NEAR_LIGHTEN, &"pale": PALE, &"lit_lighten": LIT_LIGHTEN, &"lit_glow": LIT_GLOW, &"warm": WARM, &"glow": GLOW, &"glow_alpha": GLOW_ALPHA}
## The shader keeps a state for this many tiles (a pair's tile in a row, or on
## a sign); past MAX_PAIRS (three bands) a stage warns, and tiles from the last
## slot on share its state.
const MAX_STATES := 64
const MAX_PAIRS := 30
## Receivers are traced every way at most this many mirrors can turn (2^n
## traces); a stage with more traces the first this many.
const LIGHT_MIRRORS := 10
## A spirit this close (cm, across the floor) and this near in height (under a
## terrace's step) shows its pair.
const NEAR_CM := 120
const NEAR_HEIGHT_CM := 40
## Where a row may go from its place, nearest first: its place, then steps of
## STEP in eight directions, out to RINGS steps.
const STEP := 0.12
const RINGS := 10
## A control with no room on its own floor shows its tile on a floor this near.
const BESIDE := 1.0
## Which end of a pair a hand-placed tile marks.
const CONTROL := &"control"
const GATE := &"gate"
const SIGN := &"sign"
## Gate keys that name a control, besides a `when` tree.
const GATE_KEYS := ["pad_id", "lever_id", "second_lever_id", "ball_pad_id"]
## The stage lists an input may come from (the receivers from its optics).
const GROUPS := ["pressure_pads", "ball_pads", "levers", "controls", "receivers"]
## Inputs whose letter the action pop-up carries, so they have no floor tile:
## levers and selectors (worked with the action button) and pressure pads (a
## pip stands on them). Ball pads keep their tile; receivers show a plaque.
const PROMPTED := ["levers", "controls", "pressure_pads"]
const PLAQUED := "receivers"
## The pop-up's chip, in the play screen's canvas pixels (1280 by 720 at the
## least): CHIP across, the letter LETTER_SHARE of its face tall, so on a
## 2400 by 1080 phone it is about 72 px with a letter about 30 px tall.
const CHIP := 48.0
## A lit chip: its face CHIP_LIT_LIGHTEN toward WARM and CHIP_LIT_BRIGHT
## brighter, keeping the pair's hue, inside a ring of amber light CHIP_GLOW
## (deeper than the floor's glow, to show on the cream button).
const CHIP_LIT_LIGHTEN := 0.3
const CHIP_LIT_BRIGHT := 1.18
const CHIP_GLOW := Color("f2b13c")

## Letter geometry ([positions, triangle indices] lying flat, LETTER_HEIGHT tall, centred), by letter.
static var _letters: Dictionary = {}
## The pop-up's letter font (FONT at the tiles' weight), made once.
static var _chip_font: FontVariation

var _world: Node3D
var _skips: Array = []
var _signs: Array = []
var _pairs: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
## Every tile drawn, by its state slot: {pair (index), gates (route ids)}.
var _tiles: Array[Dictionary] = []
var _material: ShaderMaterial
## The plaques' material: the same states, a stronger faint.
var _plaque_material: ShaderMaterial
var _node: MeshInstance3D
## Every node the kit drew this stage (the tiles, signs' tiles and plaques),
## taken down by clear().
var _made: Array[Node] = []
var _states := PackedVector2Array()
var _next := PackedVector2Array()
## The stage waiting to be laid out (prepare()), until it is first shown or read.
var _view: Dictionary = {}
## This level's frame (FRAMES), from its dressing's tag style.
var _frame: StringName = DEFAULT_FRAME

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: its overrides, pairs and tiles start over, their nodes taken
## down (a world that keeps its terrain between stages keeps no stale tile).
func clear() -> void:
	for node: Node in _made:
		if not is_instance_valid(node): continue
		if node.get_parent() != null: node.get_parent().remove_child(node)
		node.queue_free()
	_made.clear()
	_skips.clear()
	_signs.clear()
	_pairs.clear()
	_rows.clear()
	_tiles.clear()
	_material = null
	_plaque_material = null
	_node = null
	_states = PackedVector2Array()
	_view = {}

## The nodes the kit drew this stage.
func made() -> Array[Node]:
	return _made.duplicate()

## Leaves out control `control_id` (every gate when `gate_id` is ""), or every
## control of gate `gate_id` when `control_id` is "".
func skip(control_id: String, gate_id: String = "") -> void:
	_skips.append([control_id, gate_id])

## A tile the world places itself: on a sign it builds (side SIGN, `at` in
## `parent`'s space, lying in the parent's x and z).
func tag(control_id: String, side: StringName, at: Vector3, parent: Node3D) -> void:
	if side == SIGN: _signs.append({"control": control_id, "at": at, "parent": parent})

## The stage's pairs, from `view`'s wiring: {control, entity, kind (lever,
## pad or other), group (the GROUPS list it comes from), prompted (its letter
## shows in the action pop-up, not on the floor), gates (route dictionaries),
## values (route id -> the values a gate needs of a selector, [] for any),
## inputs (what a pip works for it: [{id, entity, group}], the control itself,
## or a receiver's mirrors), index}, in the order the gates meet them.
static func pairs_of(view: Dictionary, skips: Array = []) -> Array[Dictionary]:
	var groups: Dictionary = {}
	var entities := _entities(view, groups)
	var routes: Dictionary = {}
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []): routes[str(route.id)] = route
	var found: Array[Dictionary] = []
	var by_control: Dictionary = {}
	for gate: Dictionary in view.get("gates", []):
		var route_id := str(gate.get("route_id", ""))
		if not routes.has(route_id): continue
		for control: String in references(gate):
			if not entities.has(control) or _skipped(skips, control, route_id): continue
			if not by_control.has(control):
				by_control[control] = {"control": control, "entity": entities[control], "kind": _kind(view, control), "group": groups[control], "prompted": groups[control] in PROMPTED, "gates": [], "values": {}, "index": found.size()}
				found.append(by_control[control])
			if routes[route_id] not in by_control[control].gates: by_control[control].gates.append(routes[route_id])
			by_control[control].values[route_id] = _values(gate.get("when", {}), control)
	var lights := _light_inputs(view)
	for pair: Dictionary in found:
		# A receiver no mirror lights (a fixed beam) is read at itself.
		var ids: Array = lights.get(pair.control, [pair.control]) if pair.group == "receivers" else [pair.control]
		pair["inputs"] = ids.filter(func(id: String) -> bool: return entities.has(id)).map(func(id: String) -> Dictionary: return {"id": id, "entity": entities[id], "group": groups[id]})
	return found

## Per receiver, the turnable mirrors (controls of kind mirror) on any path
## that lights it, every way they can turn (BeamField, the game's own rule),
## in the stage's order: receiver id -> [mirror ids].
static func _light_inputs(view: Dictionary) -> Dictionary:
	var field: Variant = view.get("optical_field", view.get("optics", {}))
	if not field is Dictionary or (field as Dictionary).get("mirrors", []).is_empty(): return {}
	var turnable: Array[String] = []
	for control: Dictionary in view.get("controls", []):
		if str(control.get("kind", "")) == "mirror": turnable.append(str(control.id))
	var traced := turnable.slice(0, LIGHT_MIRRORS)
	var found: Dictionary = {}
	for way in range(1 << traced.size()):
		var overrides: Dictionary = {}
		for bit in range(traced.size()):
			overrides[traced[bit]] = {"orientation": "slash" if way & (1 << bit) else "backslash"}
		var light := BeamField.evaluate(field, overrides)
		if not bool(light.get("valid", false)): continue
		for receiver: String in light.signals:
			if not light.signals[receiver]: continue
			for segment: Dictionary in light.segments:
				if segment.hit_kind == "mirror" and segment.emitter_id in light.sources[receiver] and segment.hit_id in turnable:
					if not found.has(receiver): found[receiver] = []
					if segment.hit_id not in found[receiver]: found[receiver].append(segment.hit_id)
	for receiver: String in found:
		found[receiver] = turnable.filter(func(id: String) -> bool: return id in found[receiver])
	return found

## The controls a gate names: its GATE_KEYS and every reference in its `when` tree.
static func references(gate: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: String in GATE_KEYS:
		var id := str(gate.get(key, ""))
		if not id.is_empty() and id not in found: found.append(id)
	for id: String in predicate_references(gate.get("when", {})):
		if id not in found: found.append(id)
	return found

## The controls a `when` predicate reads, nested all and any included.
static func predicate_references(predicate: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for key: String in ["control_id", "signal_id", "pad_id", "lever_id"]:
		if predicate.has(key) and str(predicate[key]) not in found: found.append(str(predicate[key]))
	for key: String in ["all", "any"]:
		for child: Dictionary in predicate.get(key, []):
			for id: String in predicate_references(child):
				if id not in found: found.append(id)
	# Rules 20: a control a gate wants off (a lit fog lantern floods its path) still works it.
	if predicate.get("not") is Dictionary:
		for id: String in predicate_references(predicate["not"]):
			if id not in found: found.append(id)
	return found

## The values a `when` predicate asks of control `id` ([] when it asks none).
static func _values(predicate: Dictionary, id: String) -> Array:
	var found: Array = []
	if str(predicate.get("control_id", "")) == id and predicate.has("value"): found.append(str(predicate.value))
	for key: String in ["all", "any"]:
		for child: Dictionary in predicate.get(key, []):
			for value: String in _values(child, id):
				if value not in found: found.append(value)
	return found

## Pair `index`'s letter, band (0 for A to J, 1 for the next ten...) and colour.
static func letter_of(index: int) -> String:
	return LETTERS[index % LETTERS.length()]

static func band_of(index: int) -> int:
	return index / LETTERS.length()

static func colour_of(index: int) -> Color:
	return PALETTE[index % PALETTE.size()]

## Takes the stage to lay out once everything else on it is built: when it
## is first shown (present) or read (placed, states).
func prepare(view: Dictionary) -> void:
	_view = view

func _ensure_built() -> void:
	if _view.is_empty(): return
	var view := _view
	_view = {}
	build(view)

## Works out the stage's pairs, lays out their tiles and draws them under the
## world's terrain, now.
func build(view: Dictionary) -> void:
	_pairs = pairs_of(view, _skips)
	if _pairs.size() > MAX_PAIRS: push_warning("PairTags: %d pairs on one stage; past %d their tiles share a state and their bands crowd the letter" % [_pairs.size(), MAX_PAIRS])
	_rows = _layout(view)
	# One state slot per tile, so each lights for its own gates.
	_tiles.clear()
	var centres: Array = []
	for row: Dictionary in _rows:
		row["slots"] = {}
		for slot in range(row.pairs.size()):
			var index: int = row.pairs[slot]
			row.slots[index] = _tiles.size()
			_tiles.append({"pair": index, "gates": row.gates[index]})
			centres.append(_slot_at(row, slot))
	# Each tile's pool of light, kept off every other tile.
	var reaches := glow_reach(centres)
	var next := 0
	for row: Dictionary in _rows:
		row["reach"] = {}
		for index: int in row.pairs:
			row.reach[index] = reaches[next]
			next += 1
	var dressing: Variant = _world.get("dressing") if _world != null else null
	_frame = StringName(str(dressing.get("tag", DEFAULT_FRAME))) if dressing is Dictionary else DEFAULT_FRAME
	if not FRAMES.has(_frame): _frame = DEFAULT_FRAME
	_states.resize(MAX_STATES)
	_states.fill(Vector2.ZERO)
	var plaqued := _pairs.filter(func(pair: Dictionary) -> bool: return pair.group == PLAQUED)
	if _rows.reduce(func(sum: int, row: Dictionary) -> int: return sum + row.pairs.size(), 0) + _signs.size() + plaqued.size() > MAX_STATES: push_warning("PairTags: more tiles than the shader's %d states; the last ones share one" % MAX_STATES)
	_material = _look(FAINT_ALPHA)
	if not _rows.is_empty():
		_node = MeshInstance3D.new()
		_node.name = "PairTags"
		_node.mesh = _bake(_rows)
		_node.material_override = _material
		_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Measured row by row, like a folded batch: one mesh spanning floors at
		# several heights is still only flat tiles to code that looks for scenery.
		_node.set_meta(StaticBatch.PARTS_META, _rows.map(func(row: Dictionary) -> Array: return [Transform3D(Basis.IDENTITY, row.at), AABB(Vector3(-(row.rect as Rect2).size.x * 0.5, 0, -TAG * 0.5), Vector3((row.rect as Rect2).size.x, LIFT, TAG))]))
		_world.get("terrain").add_child(_node)
		_made.append(_node)
	for sign: Dictionary in _signs:
		var pair := _pair(str(sign.control))
		if pair.is_empty() or not is_instance_valid(sign.parent): continue
		var node := MeshInstance3D.new()
		node.name = "PairTagSign"
		# A sign's tile glows on its own face: no pool of light in the air.
		node.mesh = _bake([{"at": sign.at, "pairs": [pair.index], "slots": {pair.index: _tiles.size()}}], false)
		_tiles.append({"pair": pair.index, "gates": pair.gates.map(func(route: Dictionary) -> String: return str(route.id))})
		node.material_override = _material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(sign.parent as Node3D).add_child(node)
		_made.append(node)
	if not plaqued.is_empty(): _plaque_material = _look(PLAQUE_FAINT_ALPHA)
	for pair: Dictionary in plaqued: _plaque(pair)

## The tiles' material: the kit's LOOK, faint at `faint` (alphas per layer),
## reading the stage's states.
func _look(faint: Vector3) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	# Under the spirits' ground shadows, which are see-through too.
	material.render_priority = -1
	for uniform: StringName in LOOK:
		material.set_shader_parameter(uniform, LOOK[uniform])
	material.set_shader_parameter(&"faint_alpha", faint)
	material.set_shader_parameter(&"states", _states)
	return material

## Receiver `pair`'s plaque on its lamp post (PLAQUE_UP), facing the camera:
## an arm out from a clamp round the post, a plate with a darker rim leaning
## back until it faces the camera, its top edge clear of the post, and on it
## the pair's tile, lit for every gate the receiver works.
func _plaque(pair: Dictionary) -> void:
	var post: Dictionary = _world.call(&"_pair_receiver_post", pair.entity)
	var foot: Vector3 = pair.anchor
	var facing: Vector3 = (_world.call(&"camera_from") if _world.has_method(&"camera_from") else ViewFit.CAMERA_FROM).normalized()
	var lean := atan2(Vector2(facing.x, facing.z).length(), facing.y)
	var side := TAG * PLAQUE_SCALE * PLAQUE_MARGIN
	var radius := float(post.radius)
	var out := radius + side * 0.5 * cos(lean) + 0.02
	var mount := Node3D.new()
	mount.name = "PairTagPlaque_" + str(pair.control)
	mount.position = foot + Vector3(0, clampf(float(post.top) - foot.y - PLAQUE_BELOW_TOP, PLAQUE_LOW, PLAQUE_UP), 0)
	# Its arm points toward the camera across the floor.
	mount.rotation.y = atan2(facing.x, facing.z)
	_world.get("terrain").add_child(mount)
	_made.append(mount)
	Primitives.mesh_node(Primitives.cached_box(Vector3(0.035, 0.035, out)), Primitives.shared_material(PLAQUE_METAL.darkened(0.15)), Vector3(0, 0, out * 0.5), mount)
	Primitives.mesh_node(Primitives.cached_shape(Primitives.cylinder_mesh(radius + 0.025, 0.06)), Primitives.shared_material(PLAQUE_METAL.darkened(0.25)), Vector3(0, 0.07, 0), mount)
	var plate := Node3D.new()
	plate.position = Vector3(0, 0, out)
	plate.rotation.x = lean
	mount.add_child(plate)
	Primitives.mesh_node(Primitives.cached_box(Vector3(side, 0.022, side)), Primitives.shared_material(PLAQUE_METAL), Vector3(0, -0.012, 0), plate)
	Primitives.mesh_node(Primitives.cached_box(Vector3(side + 0.035, 0.03, side + 0.035)), Primitives.shared_material(PLAQUE_METAL.darkened(0.3)), Vector3(0, -0.03, 0), plate)
	var tile := MeshInstance3D.new()
	tile.name = "PairTagPlaqueTile"
	tile.scale = Vector3.ONE * PLAQUE_SCALE
	# The tile glows on its own face: no pool of light in the air.
	tile.mesh = _bake([{"at": Vector3.ZERO, "pairs": [pair.index], "slots": {pair.index: _tiles.size()}}], false)
	_tiles.append({"pair": pair.index, "gates": pair.gates.map(func(route: Dictionary) -> String: return str(route.id))})
	tile.material_override = _plaque_material
	tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plate.add_child(tile)

## Every tile the stage shows: {control, letter, band, index, sides (CONTROL
## and or GATE), gates (route ids), at (terrain space, the floor under its
## centre), row (its row's rect across the floor), squeezed (no clear place),
## glow (the floor its pool of light may cover while lit, glow_reach)}.
func placed() -> Array[Dictionary]:
	_ensure_built()
	var found: Array[Dictionary] = []
	for row: Dictionary in _rows:
		for slot in range(row.pairs.size()):
			var index: int = row.pairs[slot]
			var pair: Dictionary = _pairs[index]
			found.append({"control": pair.control, "letter": letter_of(index), "band": band_of(index), "index": index, "sides": row.sides[index], "gates": row.gates[index], "at": _slot_at(row, slot), "row": row.rect, "squeezed": row.squeezed, "clash": row.clash, "glow": _glow_rect(_slot_at(row, slot), row.reach[index])})
	return found

## The overrides the world declared this stage: [control, gate] per skip().
func skips() -> Array:
	return _skips.duplicate(true)

## The pairs' states now: control -> {clear, lit}, clear or lit when any of
## its tiles is; and per tile, tile_states().
func states() -> Dictionary:
	_ensure_built()
	var found: Dictionary = {}
	for pair: Dictionary in _pairs: found[pair.control] = {"clear": false, "lit": false}
	for state: Dictionary in tile_states():
		var shown: Dictionary = found[state.control]
		shown.clear = shown.clear or state.clear
		shown.lit = shown.lit or state.lit
	return found

## How far each tile's pool of light reaches from `centres` (tile centres,
## terrain space), each way: Vector4(-x, +x, -z, +z). HALO's whole pool where
## the floor is open; toward another tile on its floor (GLOW_FLOOR) only half
## way to it, so no glow lies under a neighbour and two lit neighbours keep a
## dark seam between their pools.
static func glow_reach(centres: Array) -> Array[Vector4]:
	var full := TAG * HALO * 0.5
	var found: Array[Vector4] = []
	for index in range(centres.size()):
		var at: Vector3 = centres[index]
		var reach := Vector4(full, full, full, full)
		for other in range(centres.size()):
			var d: Vector3 = centres[other] - at
			if other == index or absf(d.y) > GLOW_FLOOR: continue
			if not _glow_rect(at, reach).intersects(Rect2(d.x + at.x - TAG * 0.5, d.z + at.z - TAG * 0.5, TAG, TAG)): continue
			# Trimmed on the side the other tile lies most toward.
			if absf(d.x) >= absf(d.z):
				var half := maxf(absf(d.x) * 0.5, TAG * 0.5)
				if d.x > 0.0: reach.y = minf(reach.y, half)
				else: reach.x = minf(reach.x, half)
			else:
				var half := maxf(absf(d.z) * 0.5, TAG * 0.5)
				if d.z > 0.0: reach.w = minf(reach.w, half)
				else: reach.z = minf(reach.z, half)
		found.append(reach)
	return found

## The floor (x, z) a pool reaching `reach` (glow_reach) round `at` covers.
static func _glow_rect(at: Vector3, reach: Vector4) -> Rect2:
	return Rect2(at.x - reach.x, at.z - reach.z, reach.x + reach.y, reach.z + reach.w)

## Every tile's state now, in slot order: {control, gates, clear, lit}.
func tile_states() -> Array[Dictionary]:
	_ensure_built()
	var found: Array[Dictionary] = []
	for slot in range(_tiles.size()):
		var state := _states[mini(slot, MAX_STATES - 1)] if not _states.is_empty() else Vector2.ZERO
		found.append({"control": _pairs[_tiles[slot].pair].control, "gates": _tiles[slot].gates, "clear": state.x > 0.5, "lit": state.y > 0.5})
	return found

## Sets the tiles' states from snapshot `state`: clear while a spirit is near
## one of a pair's inputs, glowing as _tile_lit says. The same snapshot always
## gives the same states, in play and in a replay.
func present(state: Dictionary) -> void:
	_ensure_built()
	if _pairs.is_empty() or _material == null: return
	if _next.size() != MAX_STATES: _next.resize(MAX_STATES)
	_next.fill(Vector2.ZERO)
	var players: Dictionary = state.get("players", {})
	var near: Array[bool] = []
	for pair: Dictionary in _pairs: near.append(_spirit_near(pair, players))
	for index in range(_tiles.size()):
		var tile: Dictionary = _tiles[index]
		var slot := mini(index, MAX_STATES - 1)
		var lit := _tile_lit(_pairs[tile.pair], tile.gates, state)
		_next[slot] = Vector2(maxf(_next[slot].x, 1.0 if near[tile.pair] or lit else 0.0), maxf(_next[slot].y, 1.0 if lit else 0.0))
	if _next == _states: return
	var shown := _states
	_states = _next
	_next = shown
	_material.set_shader_parameter(&"states", _states)
	if _plaque_material != null: _plaque_material.set_shader_parameter(&"states", _states)

## Whether either spirit stands near one of the pair's inputs.
func _spirit_near(pair: Dictionary, players: Dictionary) -> bool:
	for input: Dictionary in pair.inputs:
		for slot: String in players:
			if _across(input, players[slot]) <= NEAR_CM: return true
	return false

## Whether a tile of `pair` at `gates` (route ids; none beside the control)
## glows: a lever's or pad's tiles while it is on; a selector's tile or a
## receiver's (at a gate, or its plaque, at every gate it works) only while
## one of its gates stands open at a value it asks.
func _tile_lit(pair: Dictionary, gates: Array, state: Dictionary) -> bool:
	if pair.kind != &"other": return _active(pair, state)
	var open: Dictionary = state.get("bridges", {})
	var value := str(state.get("controls", {}).get(str(pair.control), ""))
	for route: String in gates:
		var asked: Array = pair.values.get(route, [])
		if bool(open.get(route, false)) and (asked.is_empty() or value in asked): return true
	return false

## How far (cm, across the floor) `player` stands from `input`'s floor point
## (anchor): INF when it is not on that floor (NEAR_HEIGHT_CM) or there is none.
static func _across(input: Dictionary, player: Variant) -> float:
	var at: Vector3 = input.get("anchor", Vector3.INF)
	if not at.is_finite() or not player is Dictionary or not player.has("x") or not player.has("z"): return INF
	if absf(float(player.get("height", at.y * 100.0)) - at.y * 100.0) > NEAR_HEIGHT_CM: return INF
	return Vector2(float(player.x) - at.x * 100.0, float(player.z) - at.z * 100.0).length()

## The action pop-up's chip for the live pip in snapshot `state`: the input
## its action names (a lever, a selector, a mirror), else, with no button up,
## the nearest pressure pad of its own within NEAR_CM. badge() of that input, or {} (nothing near, or an
## input with no pair). From the snapshot alone, like the tiles, so it never
## lags the world's present().
func prompt(state: Dictionary) -> Dictionary:
	_ensure_built()
	var action: Variant = state.get("context_action", {})
	# A button that is up names its own input or none: a pad's letter never
	# rides on a bell, a ball or an unwired lever.
	if action is Dictionary and not str(action.get("label", "")).is_empty():
		var target := str(action.get("target_id", ""))
		for pair: Dictionary in _pairs:
			for input: Dictionary in pair.inputs:
				if input.id == target and input.group in PROMPTED: return _badge(pair, state, input)
		return {}
	var slot := str(state.get("active_slot", ""))
	var player: Variant = state.get("players", {}).get(slot)
	var best: Array = []
	var nearest := float(NEAR_CM)
	for pair: Dictionary in _pairs:
		for input: Dictionary in pair.inputs:
			if input.group != "pressure_pads" or str(input.entity.get("owner_slot", slot)) != slot: continue
			var across := _across(input, player)
			if across <= nearest:
				nearest = across
				best = [pair, input]
	return {} if best.is_empty() else _badge(best[0], state, best[1])

## Control `id`'s chip in snapshot `state`: {control, letter, band, colour,
## frame, lit}; {} for a control with no pair. The same letter, band and
## colour its tiles show; lit by the same rule that lights them.
## A lever's or pad's chip lights while it is on or held; a mirror's (an
## input of a receiver's pair) while the light reaches the receiver now (the
## snapshot's optics signals); a selector's never, as it has no off: its
## bubble shows the value and its gate tiles what that value opens.
func badge(id: String, state: Dictionary) -> Dictionary:
	_ensure_built()
	var pair := _pair(id)
	return {} if pair.is_empty() else _badge(pair, state, pair.inputs[0] if not pair.inputs.is_empty() else {})

func _badge(pair: Dictionary, state: Dictionary, input: Dictionary) -> Dictionary:
	var index: int = pair.index
	var lit := false
	if pair.group == "receivers": lit = bool(state.get("optics", {}).get("signals", {}).get(str(pair.control), false))
	elif pair.kind != &"other": lit = _active(pair, state)
	return {"control": str(pair.control), "input": str(input.get("id", pair.control)), "letter": letter_of(index), "band": band_of(index), "colour": colour_of(index), "frame": _frame, "lit": lit}

## Whether a lever is on or a pad held now (a selector or receiver is read
## through its gates, _tile_lit).
func _active(pair: Dictionary, state: Dictionary) -> bool:
	var id := str(pair.control)
	match pair.kind:
		&"lever": return bool(state.get("levers", {}).get(id, false))
		&"pad": return bool(state.get("hold_pads", {}).get(id, false))
	return false

func _pair(control: String) -> Dictionary:
	for pair: Dictionary in _pairs:
		if pair.control == control: return pair
	return {}

static func _skipped(skips: Array, control: String, gate: String) -> bool:
	for entry: Array in skips:
		if (entry[0] == control or str(entry[0]).is_empty()) and (str(entry[1]).is_empty() or entry[1] == gate): return true
	return false

## How a control is worked: a lever, a pad (held), or anything else (a
## selector, a receiver) read through its gates.
static func _kind(view: Dictionary, id: String) -> StringName:
	for lever: Dictionary in view.get("levers", []):
		if str(lever.get("id", "")) == id: return &"lever" if str(lever.get("kind", "")) != "selector" else &"other"
	for pad: Dictionary in view.get("pressure_pads", []) + view.get("ball_pads", []):
		if str(pad.get("id", "")) == id: return &"pad"
	return &"other"

## Every input of `view` by id; `groups` gets each one's GROUPS list (the
## later list wins an id two lists share, as the entity does).
static func _entities(view: Dictionary, groups: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for group: String in GROUPS:
		var listed: Array = view.get("optics", {}).get("receivers", view.get("optical_field", {}).get("receivers", [])) if group == "receivers" else view.get(group, [])
		for entity: Dictionary in listed:
			if not entity.has("id") or not entity.has("position_cm"): continue
			found[str(entity.id)] = entity
			groups[str(entity.id)] = group
	return found

# --- Layout -----------------------------------------------------------------------

## Rows: {at (floor point of the row's centre), pairs (indices left to right),
## sides and gates per index, rect, squeezed, clash}.
func _layout(view: Dictionary) -> Array[Dictionary]:
	# Each place a tile belongs: beside its control, and at each gate it works.
	var places: Array[Dictionary] = []
	var floors := FloorSpots.floors_of(view)
	for pair: Dictionary in _pairs:
		var anchor: Vector3 = _world.call(&"_pair_control_anchor", pair.entity)
		pair["anchor"] = anchor
		# The near state reads every input's floor point, tile or not.
		for input: Dictionary in pair.inputs:
			input["anchor"] = anchor if input.id == pair.control else _world.call(&"_pair_control_anchor", input.entity)
		# A prompted input's letter is in the action pop-up, a receiver's on its
		# plaque (_plaque), not on the floor.
		if pair.prompted or pair.group == PLAQUED: continue
		# Beside the control on its floor, else on the nearest floor beside it
		# (a bucket hanging in a shaft shows its tile on the rim above).
		var ends: Array = [anchor]
		for f: Dictionary in floors:
			if f.crossing or absf(float(f.y) - anchor.y) < 0.06: continue
			var rect: Rect2 = f.rect
			var nearest := Vector2(clampf(anchor.x, rect.position.x, rect.end.x), clampf(anchor.z, rect.position.y, rect.end.y))
			if nearest.distance_to(_flat(anchor)) <= BESIDE: ends.append(Vector3(nearest.x, float(f.y), nearest.y))
		places.append({"kind": CONTROL, "at": anchor, "ends": ends, "pairs": [pair.index], "sides": {pair.index: [CONTROL]}, "gates": {pair.index: []}, "surfaces": []})
	for pair: Dictionary in _pairs:
		for route: Dictionary in pair.gates:
			var ends: Array = _world.call(&"_pair_gate_anchors", route)
			if ends.is_empty(): continue
			var joined := false
			# A crossing in the middle of a row of crossings (a row of stepping
			# stones), with no floor at either end, shows its tile with the row's
			# crossing that joins the same two floors for the same control.
			var homeless := not ends.any(func(end: Vector3) -> bool: return floors.any(func(f: Dictionary) -> bool: return not f.crossing and absf(float(f.y) - end.y) < 0.06 and (f.rect as Rect2).grow(0.05).has_point(_flat(end))))
			var between := [str(route.get("from_surface", "")), str(route.get("to_surface", ""))]
			for place: Dictionary in places:
				if place.kind == GATE and (place.at as Vector3).is_equal_approx(ends[0]):
					_join(place, pair.index, GATE, str(route.id))
					joined = true
			for place: Dictionary in places:
				if joined or not homeless: break
				if place.kind == GATE and pair.index in place.pairs and place.surfaces == between:
					_join(place, pair.index, GATE, str(route.id))
					joined = true
			# A gate's tiles lie on the floors its crossing joins, by its entrance
			# or, where that has no room, by its far end.
			if not joined: places.append({"kind": GATE, "at": ends[0], "ends": ends, "pairs": [pair.index], "sides": {pair.index: [GATE]}, "gates": {pair.index: [str(route.id)]}, "surfaces": [str(route.get("from_surface", "")), str(route.get("to_surface", ""))]})
	# A pair whose control's place and gate's place would touch shows once,
	# in one row; other rows step apart as they are placed.
	var merged: Array[Dictionary] = []
	for place: Dictionary in places:
		var into: Dictionary = {}
		for row: Dictionary in merged:
			if absf((row.at as Vector3).y - (place.at as Vector3).y) < 0.06 and _flat(row.at).distance_to(_flat(place.at)) < CLUSTER and (row.pairs as Array).any(func(index: int) -> bool: return index in place.pairs): into = row
		if into.is_empty():
			merged.append(place)
			continue
		for index: int in place.pairs:
			for side: StringName in place.sides[index]: _join(into, index, side, "")
			for gate: String in place.gates[index]: _join(into, index, GATE, gate)
		into.surfaces.append_array(place.surfaces)
	var avoid := _avoid(view)
	var done: Array[Dictionary] = []
	for row: Dictionary in merged:
		row.pairs.sort()
		_place(row, floors, avoid, done)
		done.append(row)
	return done

func _join(place: Dictionary, index: int, side: StringName, gate: String) -> void:
	if index not in place.pairs:
		place.pairs.append(index)
		place.sides[index] = []
		place.gates[index] = []
	if side not in place.sides[index]: place.sides[index].append(side)
	if not gate.is_empty() and gate not in place.gates[index]: place.gates[index].append(gate)

## Puts `row` at the nearest spot to its place that lies on its floor and keeps
## GAP from everything in `avoid` and from the rows already placed
## (kit/floor_spots.gd).
func _place(row: Dictionary, floors: Array, avoid: Array, done: Array[Dictionary]) -> void:
	var taken: Array = done.map(func(other: Dictionary) -> Dictionary: return {"rect": other.rect, "y": (other.at as Vector3).y, "what": "tags of " + ", ".join((other.pairs as Array).map(func(i: int) -> String: return str(_pairs[i].control)))})
	var spec := {"size": Vector2(_width(row.pairs.size()), TAG), "ends": row.get("ends", [row.at]), "surfaces": row.surfaces, "on_crossing": row.kind == CONTROL, "gap": GAP, "step": STEP, "rings": RINGS}
	var spot := FloorSpots.find(spec, floors, avoid, taken)
	row.at = spot.at
	row.rect = spot.rect
	row.clash = spot.clash
	row.squeezed = not (spot.clash as Array).is_empty()

## What a tile keeps clear of: stairs, obstacles, drops, every control's
## disc, the goal, the handoff, every ownership mark and every floor or deck
## over its own (FloorSpots.tops), so it lies on top of what a pip stands on.
func _avoid(view: Dictionary) -> Array:
	var found := FloorSpots.scenery(view, _world, OwnerMark.reach_of("p1")) + FloorSpots.tops(view)
	var marks: Variant = _world.get("owner_marks")
	if marks != null: found.append_array(marks.discs())
	return found

static func _width(count: int) -> float:
	return float(count) * TAG + float(maxi(count - 1, 0)) * GAP

static func _slot_at(row: Dictionary, slot: int) -> Vector3:
	var count: int = row.pairs.size()
	return row.at + Vector3((float(slot) - float(count - 1) * 0.5) * (TAG + GAP), 0, 0)

static func _flat(at: Vector3) -> Vector2:
	return FloorSpots.flat(at)

# --- Drawing ------------------------------------------------------------------------

## One mesh for `rows`: first every tile's glow (its pool, row.reach, under
## every tile; without `glows`, none), then per tile its rim, face, bands and
## letter, each vertex carrying its tile's state slot (UV2.x, row.slots) and
## layer (UV2.y), drawn in that order.
func _bake(rows: Array, glows: bool = true) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for row: Dictionary in rows if glows else []:
		var count: int = row.pairs.size()
		for slot in range(count):
			var index: int = row.pairs[slot]
			_glow(tool, _slot_at(row, slot) + Vector3(0, LIFT, 0), row.reach[index], int(row.slots[index]))
	for row: Dictionary in rows:
		var count: int = row.pairs.size()
		for slot in range(count):
			var index: int = row.pairs[slot]
			var state: int = row.slots[index]
			var at: Vector3 = row.at + Vector3((float(slot) - float(count - 1) * 0.5) * (TAG + GAP), 0, 0)
			var floor_at := at + Vector3(0, LIFT, 0)
			_token(tool, floor_at, _frame, index, state)
			# Past J: upright bands down the face's edges, left then right, clear of the letter.
			var face := TAG * FACE
			for band in range(band_of(index)):
				var x := (face * 0.5 - BAND * 1.5) * (-1.0 if band % 2 == 0 else 1.0)
				_quad(tool, floor_at + Vector3(x, 0, -FACE_UP), Vector2(BAND, face * 0.7), INK, state, 2.0)
			var letter: Array = _letter(letter_of(index))
			var positions: PackedVector3Array = letter[0]
			tool.set_color(INK)
			tool.set_uv2(Vector2(float(mini(state, MAX_STATES - 1)), 2.0))
			for vertex: int in letter[1]: tool.add_vertex(at + Vector3(0, LIFT, 0) + positions[vertex])
	return tool.commit()

## A tile's frame (its raised edge, outline and details) and its coloured face
## (pair `index`'s colour), on state slot `slot`.
static func _token(tool: SurfaceTool, at: Vector3, frame: StringName, index: int, slot: int) -> void:
	var look: Dictionary = FRAMES[frame]
	var colour: Color = look.colour
	var outline := _chipped() if look.has("chipped") else _rounded(Vector2(TAG, TAG), TAG * float(look["round"]))
	_fan(tool, at + Vector3(0, 0, EDGE), outline, colour.darkened(0.3), slot, 0.0)
	_fan(tool, at, outline, colour, slot, 0.0)
	if look.has("planks"):
		for z: float in [-0.14, 0.16]:
			_quad(tool, at + Vector3(0, 0, z * TAG), Vector2(TAG * 0.92, 0.006), colour.darkened(0.18), slot, 0.0)
		for x: float in [-0.41, 0.41]:
			_fan(tool, at + Vector3(x * TAG, 0, -FACE_UP), _rounded(Vector2(0.018, 0.018), 0.009), colour.darkened(0.45), slot, 0.0)
	var face := TAG * FACE
	_fan(tool, at + Vector3(0, 0, -FACE_UP), _rounded(Vector2(face, face), face * FACE_ROUND), colour_of(index), slot, 1.0)

## A rounded rectangle `size` across with corners of `radius`, clockwise from above.
static func _rounded(size: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var half := size * 0.5 - Vector2(radius, radius)
	for corner: Array in [[Vector2(-half.x, -half.y), PI], [Vector2(half.x, -half.y), PI * 1.5], [Vector2(half.x, half.y), 0.0], [Vector2(-half.x, half.y), PI * 0.5]]:
		for step in range(6):
			var angle: float = corner[1] + PI * 0.5 * float(step) / 5.0
			points.append(corner[0] + Vector2(cos(angle), sin(angle)) * radius)
	return points

static func _chipped() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in CHIPPED: points.append(point * TAG)
	return points

## A convex `outline` (x, z around `centre`) as one fan, its state slot and layer on every vertex.
static func _fan(tool: SurfaceTool, centre: Vector3, outline: PackedVector2Array, colour: Color, slot: int, layer: float) -> void:
	tool.set_color(colour)
	tool.set_uv2(Vector2(float(mini(slot, MAX_STATES - 1)), layer))
	tool.set_uv(Vector2(0.5, 0.5))
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		tool.add_vertex(centre)
		tool.add_vertex(centre + Vector3(a.x, 0, a.y))
		tool.add_vertex(centre + Vector3(b.x, 0, b.y))

## A tile's pool of light round `at`: four quarters, each reaching its own
## way (glow_reach), its UV running 0 at the centre to 1 at that quarter's
## edges, so the shader's falloff ends exactly there.
static func _glow(tool: SurfaceTool, at: Vector3, reach: Vector4, slot: int) -> void:
	tool.set_color(GLOW)
	tool.set_uv2(Vector2(float(mini(slot, MAX_STATES - 1)), 3.0))
	for x: float in [-reach.x, reach.y]:
		for z: float in [-reach.z, reach.w]:
			var corners := [at, at + Vector3(x, 0, 0), at + Vector3(x, 0, z), at + Vector3(0, 0, z)]
			var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for vertex: int in [0, 1, 2, 0, 2, 3]:
				tool.set_uv(uvs[vertex])
				tool.add_vertex(corners[vertex])

static func _quad(tool: SurfaceTool, centre: Vector3, size: Vector2, colour: Color, slot: int, layer: float) -> void:
	tool.set_color(colour)
	tool.set_uv2(Vector2(float(mini(slot, MAX_STATES - 1)), layer))
	var half := size * 0.5
	var corners := [centre + Vector3(-half.x, 0, -half.y), centre + Vector3(half.x, 0, -half.y), centre + Vector3(half.x, 0, half.y), centre + Vector3(-half.x, 0, half.y)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for vertex: int in [0, 1, 2, 0, 2, 3]:
		tool.set_uv(uvs[vertex])
		tool.add_vertex(corners[vertex])

## A letter lying flat, LETTER_HEIGHT tall and centred on the face (a little
## up, with it): [positions, triangle indices], the game's rounded Fredoka
## letter made flat once (TextMesh) and laid on the floor, its top away from
## the camera.
static func _letter(letter: String) -> Array:
	if _letters.has(letter): return _letters[letter]
	SessionRelease.on_exit(release_cached)
	var font := FontVariation.new()
	font.base_font = FONT
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	var text := TextMesh.new()
	text.font = font
	text.font_size = 64
	text.depth = 0.0
	text.text = letter
	var arrays := text.get_mesh_arrays()
	var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for vertex: Vector3 in source:
		low = low.min(Vector2(vertex.x, vertex.y))
		high = high.max(Vector2(vertex.x, vertex.y))
	var scale := LETTER_HEIGHT / maxf(high.y - low.y, 0.0001)
	var middle := (low + high) * 0.5
	var positions := PackedVector3Array()
	for vertex: Vector3 in source: positions.append(Vector3((vertex.x - middle.x) * scale, 0, -(vertex.y - middle.y) * scale - FACE_UP))
	var triangles := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array and not (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty(): triangles = arrays[Mesh.ARRAY_INDEX]
	else:
		for i in range(positions.size()): triangles.append(i)
	# Third: its height in font pixels at size 64 (TextMesh's 0.01 m a pixel).
	_letters[letter] = [positions, triangles, (high.y - low.y) / text.pixel_size]
	return _letters[letter]

## Lets go of the letter meshes and the pop-up's font (SessionRelease at exit; tests).
static func release_cached() -> void:
	_letters.clear()
	_chip_font = null

# --- The pop-up chip --------------------------------------------------------------

## A chip's face colour: the near tile's face, or lit, the lit fill a little
## brighter (a screen has no light to glow in).
static func chip_face(colour: Color, lit: bool) -> Color:
	if not lit: return colour.lerp(PALE, NEAR_LIGHTEN)
	return (colour.lerp(WARM, CHIP_LIT_LIGHTEN) * CHIP_LIT_BRIGHT).clamp()

## Draws `chip` (badge()) on `canvas` filling the square `rect`, as its floor
## tile looks scaled up: the frame by its style (its darker edge below it and
## a fine outline, so a cream frame still reads on a cream button), the face
## in the pair's colour and the letter and bands in ink; lit, the frame warms,
## the face brightens and a soft pool of warm light lies behind it.
static func draw_chip(canvas: CanvasItem, rect: Rect2, chip: Dictionary) -> void:
	if chip.is_empty(): return
	var unit := rect.size.x / TAG
	var centre := rect.get_center()
	var lit := bool(chip.get("lit", false))
	var frame := StringName(str(chip.get("frame", DEFAULT_FRAME)))
	var look: Dictionary = FRAMES.get(frame, FRAMES[DEFAULT_FRAME])
	var colour: Color = look.colour
	if lit: colour = colour.lerp(WARM, LIT_LIGHTEN)
	var outline := _chipped() if look.has("chipped") else _rounded(Vector2(TAG, TAG), TAG * float(look["round"]))
	if lit:
		# Rings of light round the frame, fading outward.
		for ring in range(3):
			var grow := 1.3 - 0.1 * float(ring)
			var halo := PackedVector2Array()
			for point: Vector2 in outline: halo.append(point * grow)
			_chip_fill(canvas, halo, centre, unit, Color(CHIP_GLOW, 0.3 + 0.2 * float(ring)))
	var edge := maxf(EDGE * unit, 2.0)
	_chip_fill(canvas, outline, centre + Vector2(0, edge), unit, colour.darkened(0.3))
	_chip_fill(canvas, outline, centre, unit, colour, colour.darkened(0.45))
	if look.has("planks"):
		for z: float in [-0.14, 0.16]:
			canvas.draw_rect(Rect2(centre + Vector2(-0.46 * TAG, z * TAG - 0.003) * unit, Vector2(0.92 * TAG, 0.006) * unit), colour.darkened(0.18))
		for x: float in [-0.41, 0.41]:
			canvas.draw_circle(centre + Vector2(x * TAG, -FACE_UP) * unit, 0.009 * unit, colour.darkened(0.45))
	var face := TAG * FACE
	var face_centre := centre + Vector2(0, -FACE_UP) * unit
	_chip_fill(canvas, _rounded(Vector2(face, face), face * FACE_ROUND), face_centre, unit, chip_face(chip.colour, lit), Color(chip.colour).darkened(0.25))
	for band in range(int(chip.get("band", 0))):
		var x := (face * 0.5 - BAND * 1.5) * (-1.0 if band % 2 == 0 else 1.0)
		canvas.draw_rect(Rect2(face_centre + Vector2(x - BAND * 0.5, -face * 0.35) * unit, Vector2(BAND, face * 0.7) * unit), INK)
	# The letter LETTER_SHARE of the face tall, its caps centred on the face.
	var font := _chip_font_get()
	var size := int(roundf(LETTER_HEIGHT * unit / _cap_share()))
	var letter := str(chip.letter)
	var wide := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var baseline := face_centre.y + LETTER_HEIGHT * unit * 0.5
	canvas.draw_string(font, Vector2(face_centre.x - wide * 0.5, baseline), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)

static func _chip_fill(canvas: CanvasItem, outline: PackedVector2Array, centre: Vector2, unit: float, colour: Color, line: Color = Color(0, 0, 0, 0)) -> void:
	var points := PackedVector2Array()
	for point: Vector2 in outline: points.append(centre + point * unit)
	canvas.draw_colored_polygon(points, colour)
	# A fine smooth edge: the polygon itself is drawn without antialiasing.
	points.append(points[0])
	canvas.draw_polyline(points, line if line.a > 0.0 else colour, 1.2, true)

static func _chip_font_get() -> FontVariation:
	if _chip_font == null:
		SessionRelease.on_exit(release_cached)
		_chip_font = FontVariation.new()
		_chip_font.base_font = FONT
		_chip_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	return _chip_font

## A capital's height as a share of the font size: the flat letter E's
## (_letter: its height in font pixels at size 64) over 64.
static func _cap_share() -> float:
	if not _letters.has("E"): _letter("E")
	return float(_letters["E"][2]) / 64.0

## How many letters are cached (tests).
static func cached_letters() -> int:
	return _letters.size()
