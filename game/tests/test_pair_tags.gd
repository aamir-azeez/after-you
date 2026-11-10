extends SceneTree
## Pair tags (presentation/kit/pair_tags.gd), worked out from each stage's
## control-to-gate wiring, in every stage of every chapter that shows them:
## - every wired control shows its tile beside it and at every gate it works,
##   unless its world skips it (pair_tags.skip), with one letter per control,
##   none shared on a stage;
## - every tile lies on its floor, clear of controls, ownership marks, decks,
##   the world's own scenery and every other row, and no two rows touch;
## - one mesh draws them all, and the states follow the snapshot alone:
##   faint, clear while either spirit is near, glowing while active, the
##   same whatever came before (a replay shows what play showed).
## The pure parts are checked on small stages too: no pairs, past ten, a
## missing gate or control, a gate several controls work. A failure names the
## chapter, the stage and what clashed.
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## Colours this far apart (CIE76) never pass for one another.
const COLOUR_GAP := 20.0
## Laying out a stage's tiles stays under this (headless, the whole stage).
const BUILD_BUDGET_USEC := 150000
var checks := 0
var failures := 0
var _slowest := [0, ""]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_palette()
	_pure()
	var tagged := 0
	var stages := 0
	for key: String in Registry.keys():
		var world: Node3D = Registry.world_script(key).new()
		if not "pair_tags" in world:
			world.free()
			continue
		root.add_child(world)
		world.set_process(false)
		var level := Registry.definition(key)
		var digest := Canonical.digest(level)
		world.load_level(level)
		for stage: Dictionary in level.stages:
			world.show_stage(stage)
			tagged += _stage(world, key, CooperativeCatalog.stage_definition(level, str(stage.id)))
			stages += 1
		_check(Canonical.digest(level) == digest, "%s: tags never change the definition" % key)
		world.free()
	_check(stages > 10 and tagged > 40, "The sweep sees the chapters' pair tags: %d tiles on %d stages" % [tagged, stages])
	print("PAIR TAGS: slowest layout %.1f ms (%s)" % [float(_slowest[0]) / 1000.0, _slowest[1]])
	_check(PairTags.cached_letters() > 0, "Letters are cached once made")
	_check(SessionRelease._releases.has(Callable(PairTags, "release_cached")), "The letter cache lets go at session end (SessionRelease)")
	PairTags.release_cached()
	_check(PairTags.cached_letters() == 0, "release_cached() lets every letter go")
	print("PAIR TAGS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Ten colours apart from each other and from the owners' gold and teal.
func _palette() -> void:
	var colours: Array = PairTags.PALETTE
	_check(colours.size() == PairTags.LETTERS.length(), "One colour per letter")
	for index in range(colours.size()):
		for owner: Color in [OwnerMark.GOLD, OwnerMark.TEAL]:
			_check(_delta(colours[index], owner) >= COLOUR_GAP, "Pair colour %s stays apart from the owner colour %s (%.1f)" % [colours[index].to_html(false), owner.to_html(false), _delta(colours[index], owner)])
		for other in range(index + 1, colours.size()):
			_check(_delta(colours[index], colours[other]) >= COLOUR_GAP, "Pair colours %s and %s stay apart (%.1f)" % [colours[index].to_html(false), colours[other].to_html(false), _delta(colours[index], colours[other])])

## The wiring, the letters and the bands on small stages.
func _pure() -> void:
	_check(PairTags.pairs_of({}).is_empty() and PairTags.pairs_of({"gates": [{"route_id": "nowhere", "lever_id": "a"}]}).is_empty(), "No wiring, or a gate whose crossing is missing, gives no pairs")
	var many := {"bridges": [], "levers": [], "gates": []}
	for index in range(25):
		many.bridges.append({"id": "route-%d" % index, "rect_cm": [0, 0, 10, 10]})
		many.levers.append({"id": "lever-%d" % index, "position_cm": [0, 0]})
		many.gates.append({"route_id": "route-%d" % index, "lever_id": "lever-%d" % index})
	many.gates.append({"route_id": "route-0", "pad_id": "missing-pad"})
	many.gates.append({"route_id": "route-1", "when": {"all": [{"lever_id": "lever-0"}, {"any": [{"lever_id": "lever-2"}]}]}})
	var pairs := PairTags.pairs_of(many)
	_check(pairs.size() == 25, "Twenty-five wired levers make twenty-five pairs; a missing control makes none: %d" % pairs.size())
	_check(pairs[0].gates.map(func(r: Dictionary) -> String: return r.id) == ["route-0", "route-1"] and pairs[2].gates.size() == 2, "A control that works two gates shows at both; a `when` tree is read through all and any")
	var seen := {}
	for index in range(25): seen["%s%d" % [PairTags.letter_of(index), PairTags.band_of(index)]] = true
	_check(seen.size() == 25 and PairTags.letter_of(10) == "A" and PairTags.band_of(10) == 1 and PairTags.band_of(24) == 2, "Past J the letters start again with a band: every pair keeps its own letter and band")
	_check(PairTags.pairs_of(many, [["lever-3", ""], ["", "route-4"]]).size() == 23, "A skipped control, and every control of a skipped gate, make no pair")
	_check(PairTags.references({"route_id": "r", "pad_id": "p", "lever_id": "l", "second_lever_id": "m", "ball_pad_id": "b", "when": {"signal_id": "s"}}) == ["p", "l", "m", "b", "s"], "Every way a gate names a control is read")

## One stage's checks; returns how many tiles it shows.
func _stage(world: Node3D, key: String, view: Dictionary) -> int:
	var where := "%s %s" % [key, world.displayed_stage_id]
	var tags = world.pair_tags
	# The first read lays the stage out.
	var started := Time.get_ticks_usec()
	var placed: Array[Dictionary] = tags.placed()
	var spent := Time.get_ticks_usec() - started
	if spent > int(_slowest[0]): _slowest = [spent, where]
	_check(spent < BUILD_BUDGET_USEC, "%s: laying out the pair tags takes %.1f ms" % [where, float(spent) / 1000.0])
	var wired := PairTags.pairs_of(view, tags.skips())
	_check(wired.size() <= PairTags.MAX_PAIRS, "%s: %d pairs fit the shader's states and three bands (%d)" % [where, wired.size(), PairTags.MAX_PAIRS])
	# Both ends of every wired pair, one letter per control.
	var letters := {}
	for pair: Dictionary in wired:
		var tiles := placed.filter(func(tile: Dictionary) -> bool: return tile.control == pair.control)
		_check(tiles.any(func(tile: Dictionary) -> bool: return PairTags.CONTROL in tile.sides), "%s: %s shows its tile beside it" % [where, pair.control])
		for route: Dictionary in pair.gates:
			_check(tiles.any(func(tile: Dictionary) -> bool: return str(route.id) in tile.gates), "%s: %s shows its tile at the gate of %s" % [where, pair.control, route.id])
		var looks := tiles.map(func(tile: Dictionary) -> String: return "%s%d" % [tile.letter, tile.band])
		_check(not looks.is_empty() and looks.all(func(look: String) -> bool: return look == looks[0]), "%s: every tile of %s shows one letter: %s" % [where, pair.control, looks])
		if looks.is_empty(): continue
		_check(not letters.has(looks[0]), "%s: %s and %s share the letter %s" % [where, pair.control, letters.get(looks[0], ""), looks[0]])
		letters[looks[0]] = pair.control
	_check(placed.all(func(tile: Dictionary) -> bool: return wired.any(func(pair: Dictionary) -> bool: return pair.control == tile.control)), "%s: every tile belongs to a wired control" % where)
	# Each tile clear of everything, on its floor; rows apart.
	for tile: Dictionary in placed:
		_check((tile.clash as Array).is_empty(), "%s: %s's tile (%s) at %s has a clear place; it runs into %s" % [where, tile.control, tile.letter, tile.at, ", ".join(tile.clash)])
	var rows: Array = []
	for tile: Dictionary in placed:
		if tile.row not in rows: rows.append(tile.row)
	var heights := {}
	for tile: Dictionary in placed: heights[tile.row] = (tile.at as Vector3).y
	for index in range(rows.size()):
		for other in range(index + 1, rows.size()):
			if absf(float(heights[rows[index]]) - float(heights[rows[other]])) > 0.3: continue
			_check(not (rows[index] as Rect2).grow(PairTags.GAP * 0.5 - 0.001).intersects(rows[other]), "%s: two rows of tiles keep apart (%s, %s)" % [where, rows[index], rows[other]])
	# One mesh draws the stage's tiles.
	var drawn: Array = world.terrain.find_children("PairTags", "MeshInstance3D", true, false)
	_check(drawn.size() == (0 if placed.is_empty() else 1), "%s: one mesh draws every tile (%d)" % [where, drawn.size()])
	# A tile on a sign faces the camera, its letter upright.
	for sign: MeshInstance3D in world.terrain.find_children("PairTagSign", "MeshInstance3D", true, false):
		var basis := sign.global_transform.basis.orthonormalized()
		_check(basis.y.z > 0.9 and (-basis.z).y > 0.9, "%s: the sign's tile faces the camera with its letter upright" % where)
	_states(world, where, wired)
	return placed.size()

## Faint, near (either spirit), lit, and the same states whatever came before.
func _states(world: Node3D, where: String, wired: Array[Dictionary]) -> void:
	var tags = world.pair_tags
	if wired.is_empty(): return
	var far := {"players": {"p0": {"x": 99999, "z": 99999, "height": 0}, "p1": {"x": -99999, "z": -99999, "height": 0}}, "levers": {}, "hold_pads": {}, "bridges": {}}
	tags.present(far)
	_check(tags.states().values().all(func(s: Dictionary) -> bool: return not s.clear and not s.lit), "%s: with no spirit near and nothing active every tile is faint" % where)
	var pair: Dictionary = wired[0]
	var at: Vector3 = world._pair_control_anchor(pair.entity)
	for slot: String in ["p0", "p1"]:
		var near := far.duplicate(true)
		near.players[slot] = {"x": at.x * 100.0 + 30.0, "z": at.z * 100.0, "height": at.y * 100.0}
		tags.present(near)
		var shown: Dictionary = tags.states()
		_check(shown[pair.control].clear and not shown[pair.control].lit, "%s: %s shows clearly while %s stands near it" % [where, pair.control, slot])
		_check(shown.keys().filter(func(id: String) -> bool: return id != pair.control and shown[id].clear).all(func(id: String) -> bool: return _near(world, wired, id, near)), "%s: only pairs a spirit is near show clearly" % where)
	# Each pair glows while active, by the one thing that makes its kind active.
	var active := far.duplicate(true)
	for each: Dictionary in wired:
		var alone := far.duplicate(true)
		_activate(alone, each)
		tags.present(alone)
		var shown: Dictionary = tags.states()
		_check(shown[each.control].lit and shown[each.control].clear, "%s: %s (a %s) glows at both ends while active" % [where, each.control, each.kind])
		_check(not shown.keys().any(func(id: String) -> bool: return id != each.control and shown[id].lit and not _lit_by(wired, id, alone)), "%s: activating %s lights no other pair" % [where, each.control])
	_activate(active, pair)
	# Out of order: the same snapshot gives the same states after any other.
	tags.present(far)
	var before: Dictionary = tags.states()
	tags.present(active)
	tags.present(far)
	_check(tags.states() == before, "%s: a snapshot shows the same states whatever came before" % where)

## Makes `pair` active in `state` the way its kind is read.
static func _activate(state: Dictionary, pair: Dictionary) -> void:
	match pair.kind:
		&"lever": state.levers[pair.control] = true
		&"pad": state.hold_pads[pair.control] = true
		_:
			var route: Dictionary = pair.gates[0]
			state.bridges[str(route.id)] = true
			var asked: Array = pair.values.get(str(route.id), [])
			if not asked.is_empty():
				if not state.has("controls"): state["controls"] = {}
				state.controls[pair.control] = asked[0]

## Whether pair `id` is active in `state` on its own account (an open gate it shares).
static func _lit_by(wired: Array[Dictionary], id: String, state: Dictionary) -> bool:
	for pair: Dictionary in wired:
		if pair.control != id: continue
		match pair.kind:
			&"lever": return bool(state.levers.get(id, false))
			&"pad": return bool(state.hold_pads.get(id, false))
		for route: Dictionary in pair.gates:
			var asked: Array = pair.values.get(str(route.id), [])
			if bool(state.bridges.get(str(route.id), false)) and (asked.is_empty() or str(state.get("controls", {}).get(id, "")) in asked): return true
	return false

func _near(world: Node3D, wired: Array[Dictionary], id: String, state: Dictionary) -> bool:
	for pair: Dictionary in wired:
		if pair.control != id: continue
		var at: Vector3 = world._pair_control_anchor(pair.entity)
		for player: Dictionary in state.players.values():
			if Vector2(float(player.x) - at.x * 100.0, float(player.z) - at.z * 100.0).length() <= PairTags.NEAR_CM: return true
	return false

## CIE76 distance between two colours.
static func _delta(a: Color, b: Color) -> float:
	var x := _lab(a)
	var y := _lab(b)
	return x.distance_to(y)

static func _lab(colour: Color) -> Vector3:
	var linear := colour.srgb_to_linear()
	var x := (0.4124 * linear.r + 0.3576 * linear.g + 0.1805 * linear.b) / 0.95047
	var y := 0.2126 * linear.r + 0.7152 * linear.g + 0.0722 * linear.b
	var z := (0.0193 * linear.r + 0.1192 * linear.g + 0.9505 * linear.b) / 1.08883
	var f := func(t: float) -> float: return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
