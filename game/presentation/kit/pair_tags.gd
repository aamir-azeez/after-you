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
## not an input: it keeps a tile that lights only while its gate stands open,
## and its inputs are the mirrors on the paths that light it (_light_inputs),
## which carry its letter in the pop-up and show its pair near. A gate several controls work
## shows their tiles side by side in one short row; a control whose tile and
## gate tile would touch shows it once, and every row is placed on its own
## floor clear of the controls, the ownership marks, the decks and other rows,
## by the gate's entrance or, without room there, by its far end. A world overrides with skip() (a control or gate it shows some other
## way) and tag() (a tile on a sign it builds itself); it supplies the floor
## point of a control (_pair_control_anchor), of a gate's crossing's ends,
## the entrance first (_pair_gate_anchors) and anything else of its own a tile keeps clear of
## (_pair_keep_clear: discs {centre, radius} or {rect}, with an optional y).
##
## States, from the snapshot alone and per tile: faint (a soft wash of the
## colour and a whisper of the letter), near (full colour, a lighter face, a
## solid letter) while either spirit stands within NEAR_CM of one of the
## pair's inputs on its floor, and lit (a bright glowing fill, its ink letter,
## and a pool of warm light around the tile): a lever's or pad's tiles while
## it is on or held; a selector's or receiver's tile at a gate only while that
## gate stands open at a value it asks of the selector, so a selector lights
## the one gate end its value opens; a receiver's own tile while any of its
## gates is open. The world
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
## tile adds one small mesh); present() works out the states, a few distance
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
const SHADER := preload("res://presentation/kit/pair_tags.gdshader")
## A tile is TAG across; tiles keep GAP from each other and from what they avoid.
const TAG := 0.28
const GAP := 0.05
## Tags whose places are closer than this (same floor) join one row.
const CLUSTER := 0.34
## Every layer (rim, face, bands, letter) lies this far over the floor: 3 mm or
## more from the floor lines' tops (6 mm, kit/surfaces.gd) and a crossing's
## remembered footsteps (13.5 mm), under a spirit's ground shadow. The layers
## write no depth and draw in order, so they share the height.
const LIFT := 0.0095
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
## times the tile across under it, GLOW_ALPHA strong at its centre.
const FAINT_ALPHA := Vector3(0.18, 0.2, 0.14)
const NEAR_LIGHTEN := 0.1
const PALE := Color("fff8e0")
const LIT_LIGHTEN := 0.45
const LIT_GLOW := 0.5
const WARM := Color("ffdc94")
const GLOW := Color("ffe696")
const HALO := 3.6
const GLOW_ALPHA := 0.9
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
## pip stands on them). Ball pads and receivers keep their tile.
const PROMPTED := ["levers", "controls", "pressure_pads"]
## The pop-up's chip, in the play screen's canvas pixels (1280 by 720 at the
## least): CHIP across, the letter LETTER_SHARE of its face tall, so on a
## 2400 by 1080 phone it is about 72 px with a letter about 30 px tall.
const CHIP := 48.0

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
var _node: MeshInstance3D
var _states := PackedVector2Array()
var _next := PackedVector2Array()
## The stage waiting to be laid out (prepare()), until it is first shown or read.
var _view: Dictionary = {}
## This level's frame (FRAMES), from its dressing's tag style.
var _frame: StringName = DEFAULT_FRAME

func _init(world: Node3D = null) -> void:
	_world = world

## A new stage: its overrides, pairs and tiles start over (the nodes went with the terrain).
func clear() -> void:
	_skips.clear()
	_signs.clear()
	_pairs.clear()
	_rows.clear()
	_tiles.clear()
	_material = null
	_node = null
	_states = PackedVector2Array()
	_view = {}

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
	for row: Dictionary in _rows:
		row["slots"] = {}
		for index: int in row.pairs:
			row.slots[index] = _tiles.size()
			_tiles.append({"pair": index, "gates": row.gates[index]})
	var dressing: Variant = _world.get("dressing") if _world != null else null
	_frame = StringName(str(dressing.get("tag", DEFAULT_FRAME))) if dressing is Dictionary else DEFAULT_FRAME
	if not FRAMES.has(_frame): _frame = DEFAULT_FRAME
	_states.resize(MAX_STATES)
	_states.fill(Vector2.ZERO)
	if _rows.reduce(func(sum: int, row: Dictionary) -> int: return sum + row.pairs.size(), 0) + _signs.size() > MAX_STATES: push_warning("PairTags: more tiles than the shader's %d states; the last ones share one" % MAX_STATES)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	# Under the spirits' ground shadows, which are see-through too.
	_material.render_priority = -1
	for uniform: StringName in LOOK:
		_material.set_shader_parameter(uniform, LOOK[uniform])
	_material.set_shader_parameter(&"states", _states)
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

## Every tile the stage shows: {control, letter, band, index, sides (CONTROL
## and or GATE), gates (route ids), at (terrain space, the floor under its
## centre), row (its row's rect across the floor), squeezed (no clear place)}.
func placed() -> Array[Dictionary]:
	_ensure_built()
	var found: Array[Dictionary] = []
	for row: Dictionary in _rows:
		for slot in range(row.pairs.size()):
			var index: int = row.pairs[slot]
			var pair: Dictionary = _pairs[index]
			found.append({"control": pair.control, "letter": letter_of(index), "band": band_of(index), "index": index, "sides": row.sides[index], "gates": row.gates[index], "at": _slot_at(row, slot), "row": row.rect, "squeezed": row.squeezed, "clash": row.clash})
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

## Whether either spirit stands near one of the pair's inputs.
func _spirit_near(pair: Dictionary, players: Dictionary) -> bool:
	for input: Dictionary in pair.inputs:
		for slot: String in players:
			if _across(input, players[slot]) <= NEAR_CM: return true
	return false

## Whether a tile of `pair` at `gates` (route ids; none beside the control)
## glows: a lever's or pad's tiles while it is on; a selector's or receiver's
## tile at gates only while one of them stands open at a value it asks, and
## beside it while any of its gates does.
func _tile_lit(pair: Dictionary, gates: Array, state: Dictionary) -> bool:
	if gates.is_empty() or pair.kind != &"other": return _active(pair, state)
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
## its action names (a lever, a selector), else the nearest pressure pad of
## its own within NEAR_CM. badge() of that input, or {} (nothing near, or an
## input with no pair). From the snapshot alone, like the tiles, so it never
## lags the world's present().
func prompt(state: Dictionary) -> Dictionary:
	_ensure_built()
	var action: Variant = state.get("context_action", {})
	if action is Dictionary and not str(action.get("label", "")).is_empty():
		var target := str(action.get("target_id", ""))
		for pair: Dictionary in _pairs:
			for input: Dictionary in pair.inputs:
				if input.id == target and input.group in PROMPTED: return _badge(pair, state, input)
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
## A mirror's chip (an input of a receiver's pair) lights while the light
## reaches the receiver now (the snapshot's optics signals).
func badge(id: String, state: Dictionary) -> Dictionary:
	_ensure_built()
	var pair := _pair(id)
	return {} if pair.is_empty() else _badge(pair, state, pair.inputs[0] if not pair.inputs.is_empty() else {})

func _badge(pair: Dictionary, state: Dictionary, input: Dictionary) -> Dictionary:
	var index: int = pair.index
	var lit := bool(state.get("optics", {}).get("signals", {}).get(str(pair.control), false)) if pair.group == "receivers" else _active(pair, state)
	return {"control": str(pair.control), "input": str(input.get("id", pair.control)), "letter": letter_of(index), "band": band_of(index), "colour": colour_of(index), "frame": _frame, "lit": lit}

func _active(pair: Dictionary, state: Dictionary) -> bool:
	var id := str(pair.control)
	match pair.kind:
		&"lever": return bool(state.get("levers", {}).get(id, false))
		&"pad": return bool(state.get("hold_pads", {}).get(id, false))
	# A selector or receiver is active while a gate it works stands open with
	# the selector at a value that gate asks of it.
	var open: Dictionary = state.get("bridges", {})
	var value := str(state.get("controls", {}).get(id, ""))
	for route: Dictionary in pair.gates:
		var asked: Array = pair.values.get(str(route.id), [])
		if bool(open.get(str(route.id), false)) and (asked.is_empty() or value in asked): return true
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
		# A prompted input's letter is in the action pop-up, not on the floor.
		if pair.prompted: continue
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
			for place: Dictionary in places:
				if place.kind == GATE and (place.at as Vector3).is_equal_approx(ends[0]):
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
## disc, the goal, the handoff and every ownership mark.
func _avoid(view: Dictionary) -> Array:
	var found := FloorSpots.scenery(view, _world, OwnerMark.reach_of("p1"))
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

## One mesh for `rows`: first every tile's glow (so no glow lies over a
## neighbour; without `glows`, none), then per tile its rim, face, bands and
## letter, each vertex carrying its tile's state slot (UV2.x, row.slots) and
## layer (UV2.y), drawn in that order.
func _bake(rows: Array, glows: bool = true) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	for row: Dictionary in rows if glows else []:
		var count: int = row.pairs.size()
		for slot in range(count):
			var at: Vector3 = row.at + Vector3((float(slot) - float(count - 1) * 0.5) * (TAG + GAP), 0, 0)
			_quad(tool, at + Vector3(0, LIFT, 0), Vector2(TAG, TAG) * HALO, GLOW, int(row.slots[row.pairs[slot]]), 3.0)
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
	return (colour.lerp(WARM, LIT_LIGHTEN) * (1.0 + LIT_GLOW * 0.5)).clamp()

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
	if lit:
		for ring in range(5):
			canvas.draw_circle(centre, rect.size.x * (0.95 - 0.1 * float(ring)), Color(GLOW, GLOW_ALPHA * 0.16))
	var colour: Color = look.colour
	if lit: colour = colour.lerp(WARM, LIT_LIGHTEN)
	var outline := _chipped() if look.has("chipped") else _rounded(Vector2(TAG, TAG), TAG * float(look["round"]))
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
