extends SceneTree
## Pair tags (presentation/kit/pair_tags.gd), worked out from each stage's
## control-to-gate wiring, in every stage of every chapter that shows them:
## - every wired control shows its tile at every gate it works (the outputs),
##   unless its world skips it (pair_tags.skip), with one letter per control,
##   none shared on a stage; an input the action pop-up names (a lever, a
##   selector, a pressure pad) has no floor tile, and one it cannot (a ball
##   pad, a receiver) keeps its tile beside it;
## - the pop-up's chip (prompt, badge) carries the pair's own letter, band and
##   colour, lit by the same rule as its tiles, from the snapshot alone;
## - every tile lies on its floor, clear of controls, ownership marks, decks,
##   the world's own scenery and every other row, and no two rows touch;
## - one mesh draws them all, and the states follow the snapshot alone:
##   faint, clear while either spirit is near one of the pair's inputs,
##   glowing while active, the same whatever came before (a replay shows what
##   play showed); a selector's tile at a gate glows only at a value that gate
##   asks, and a receiver's own tile only while one of its gates is open;
## - a receiver lit through turnable mirrors has those mirrors as its inputs.
## The pure parts are checked on small stages too: no pairs, past ten, a
## missing gate or control, a gate several controls work. A failure names the
## chapter, the stage and what clashed.
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const PairTags = preload("res://presentation/kit/pair_tags.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const Canonical = preload("res://core/v2/canonical.gd")
const ChapterControls = preload("res://presentation/chapter_controls.gd")
## Colours this far apart (CIE76) never pass for one another.
const COLOUR_GAP := 20.0
## The three states stay this far apart (CIE76) for every pair colour on every
## floor colour: a tile's face from faint to near and from near to lit, and
## its ink letter against a near and a lit face. A guard on the kit's numbers;
## the captures (private tools) measure the rendered pixels.
const FAINT_TO_NEAR := 10.0
const NEAR_TO_LIT := 25.0
const LETTER_ON_FACE := 30.0
## The floors tiles lie on: cream stone, timber, grass, terracotta tile, grey stone.
const FLOORS := [Color("e9dcc0"), Color("6b5240"), Color("9cb86a"), Color("f2a07a"), Color("b4c5bd")]
## The light a floor tile meets, about, in the chapters' sun.
const LIGHT := 0.9
## Laying out a stage's tiles stays under this (headless, the whole stage).
const BUILD_BUDGET_USEC := 150000
var checks := 0
var failures := 0
var _slowest := [0, ""]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_palette()
	_state_gaps()
	_letter_size()
	_chip_size()
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
		# The frame follows the level's tag style: the harbour's plaque on the tide.
		var style := str(world.dressing.get("tag", PairTags.DEFAULT_FRAME))
		_check(world.pair_tags._frame == StringName(style) and (style == "wooden_plaque") == key.begins_with("turn-of-the-tide"), "%s: tags wear its %s frame (%s)" % [key, style, world.pair_tags._frame])
		_check(Canonical.digest(level) == digest, "%s: tags never change the definition" % key)
		world.free()
	_hud()
	_check(stages > 10 and tagged > 30, "The sweep sees the chapters' pair tags: %d tiles on %d stages" % [tagged, stages])
	print("PAIR TAGS: slowest layout %.1f ms (%s)" % [float(_slowest[0]) / 1000.0, _slowest[1]])
	_check(PairTags.cached_letters() > 0, "Letters are cached once made")
	_check(SessionRelease._releases.has(Callable(PairTags, "release_cached")), "The letter cache lets go at session end (SessionRelease)")
	PairTags.release_cached()
	_check(PairTags.cached_letters() == 0, "release_cached() lets every letter go")
	print("PAIR TAGS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The play screen asks the shown world's pair tags for its chip: at a lever
## of Slack Water the action button carries its letter at its left end (room
## kept by an empty icon), at a pad the chip stands alone in that spot, and
## far from every input, in the memory's wait or out of play there is none.
func _hud() -> void:
	const KEY := "turn-of-the-tide@1"
	var world: Node3D = Registry.world_script(KEY).new()
	root.add_child(world)
	world.set_process(false)
	var level := Registry.definition(KEY)
	world.load_level(level)
	world.show_stage(level.stages[1])
	var controls := ChapterControls.new()
	root.add_child(controls)
	controls.watch_view(world)
	var view := CooperativeCatalog.stage_definition(level, str(level.stages[1].id))
	var wired := PairTags.pairs_of(view, world.pair_tags.skips())
	var lever: Dictionary = wired.filter(func(pair: Dictionary) -> bool: return pair.kind == &"lever")[0]
	var slot := str(lever.entity.owner_slot)
	var at: Vector3 = world._pair_control_anchor(lever.entity)
	var far := {"active_slot": slot, "players": {"p0": {"x": 99999, "z": 99999, "height": 0}, "p1": {"x": -99999, "z": -99999, "height": 0}}, "levers": {}, "hold_pads": {}, "bridges": {}, "context_action": {"id": "", "label": "", "enabled": false, "target_id": ""}}
	var near := far.duplicate(true)
	near.players[slot] = {"x": at.x * 100.0, "z": at.z * 100.0, "height": at.y * 100.0}
	near["context_action"] = {"id": "lever", "label": "Pull chain", "enabled": true, "target_id": lever.control}
	controls.update_state("", 10.0, near, true)
	var chip := controls.pair_chip
	var button := controls.action_button
	_check(chip.visible and chip.chip.get("letter", "") == PairTags.letter_of(lever.index) and button.visible and button.icon != null, "At %s the action button shows its letter %s: %s" % [lever.control, PairTags.letter_of(lever.index), chip.chip])
	_check(Rect2(button.position, button.size).encloses(Rect2(chip.position, chip.size)), "The chip sits inside the action button: %s in %s" % [Rect2(chip.position, chip.size), Rect2(button.position, button.size)])
	var on := near.duplicate(true)
	on.levers[lever.control] = true
	controls.update_state("", 10.0, on, true)
	_check(chip.visible and chip.chip.lit, "The chip lights while %s is on" % lever.control)
	controls.update_state("", 10.0, near, false)
	_check(not chip.visible and button.icon == null, "Out of play there is no chip")
	controls.update_state("", 10.0, far, true)
	_check(not chip.visible and not button.visible and button.icon == null, "Far from every input there is no chip and no button")
	# Set the Tide has the bollard pad.
	world.show_stage(level.stages[0])
	view = CooperativeCatalog.stage_definition(level, str(level.stages[0].id))
	wired = PairTags.pairs_of(view, world.pair_tags.skips())
	var pads := wired.filter(func(pair: Dictionary) -> bool: return pair.group == "pressure_pads")
	_check(not pads.is_empty(), "Set the Tide has a pad for the chip check")
	if not pads.is_empty():
		var pad: Dictionary = pads[0]
		var on_pad := far.duplicate(true)
		on_pad.active_slot = str(pad.entity.owner_slot)
		var spot: Vector3 = world._pair_control_anchor(pad.entity)
		on_pad.players[on_pad.active_slot] = {"x": spot.x * 100.0, "z": spot.z * 100.0, "height": spot.y * 100.0}
		controls.update_state("", 10.0, on_pad, true)
		_check(chip.visible and not button.visible and chip.chip.get("control", "") == pad.control, "On the pad %s its chip stands alone in the button's spot: %s" % [pad.control, chip.chip])
	controls.free()
	world.free()

## Ten colours apart from each other and from the owners' gold and teal.
func _palette() -> void:
	var colours: Array = PairTags.PALETTE
	_check(colours.size() == PairTags.LETTERS.length(), "One colour per letter")
	for index in range(colours.size()):
		for owner: Color in [OwnerMark.GOLD, OwnerMark.TEAL]:
			_check(_delta(colours[index], owner) >= COLOUR_GAP, "Pair colour %s stays apart from the owner colour %s (%.1f)" % [colours[index].to_html(false), owner.to_html(false), _delta(colours[index], owner)])
		for other in range(index + 1, colours.size()):
			_check(_delta(colours[index], colours[other]) >= COLOUR_GAP, "Pair colours %s and %s stay apart (%.1f)" % [colours[index].to_html(false), colours[other].to_html(false), _delta(colours[index], colours[other])])

## The shader's three looks (pair_tags.gdshader with the kit's LOOK numbers),
## worked out as displayed colours, stay apart: so no change flattens them.
func _state_gaps() -> void:
	# The shader takes exactly the kit's numbers (LOOK), one uniform each.
	var declared: Array = []
	for found: RegExMatch in RegEx.create_from_string("(?m)^uniform\\s+\\w+\\s+(\\w+)").search_all(PairTags.SHADER.code): declared.append(found.get_string(1))
	declared.erase("states")
	var wanted: Array = PairTags.LOOK.keys().map(func(name: StringName) -> String: return str(name))
	declared.sort()
	wanted.sort()
	_check(declared == wanted, "The shader's look uniforms are the kit's LOOK: %s against %s" % [declared, wanted])
	var worst := {"near": INF, "lit": INF, "letter": INF}
	var ink := PairTags.INK * LIGHT
	for colour: Color in PairTags.PALETTE:
		var near := colour.lerp(PairTags.PALE, PairTags.NEAR_LIGHTEN) * LIGHT
		var fill := colour.lerp(PairTags.WARM, PairTags.LIT_LIGHTEN)
		var lit := (fill * LIGHT + fill * PairTags.LIT_GLOW).clamp()
		for floor_colour: Color in FLOORS:
			var faint := (floor_colour * LIGHT).lerp(colour * LIGHT, PairTags.FAINT_ALPHA.y)
			worst.near = minf(worst.near, _delta(faint, near))
			_check(_delta(faint, near) >= FAINT_TO_NEAR, "A near tile stands off a faint one: %s on %s (%.1f)" % [colour.to_html(false), floor_colour.to_html(false), _delta(faint, near)])
		worst.lit = minf(worst.lit, _delta(near, lit))
		worst.letter = minf(worst.letter, minf(_delta(ink, near), _delta(ink, lit)))
		_check(_delta(near, lit) >= NEAR_TO_LIT, "A lit tile stands off a near one: %s (%.1f)" % [colour.to_html(false), _delta(near, lit)])
		_check(_delta(ink, near) >= LETTER_ON_FACE and _delta(ink, lit) >= LETTER_ON_FACE, "The letter reads on a near and a lit face: %s (%.1f, %.1f)" % [colour.to_html(false), _delta(ink, near), _delta(ink, lit)])
	# The glow is warm light: more green than blue, a wide pool, strong at its centre.
	_check(PairTags.GLOW.g - PairTags.GLOW.b >= 0.2 and PairTags.HALO >= 3.0 and PairTags.GLOW_ALPHA >= 0.5, "A lit tile sits in a wide pool of warm light")
	print("PAIR TAGS: state gaps faint-near %.1f, near-lit %.1f, letter %.1f" % [worst.near, worst.lit, worst.letter])

## Each letter, drawn in software at 64 by 64 over the token's face, stands
## about LETTER_SHARE of it tall (never shrinking to specks, never filling the
## box), keeps a clear margin inside the face, leaves room for the bands past
## J at each edge, and every frame style is a real FRAMES entry.
func _letter_size() -> void:
	const GRID := 64
	var face := PairTags.TAG * PairTags.FACE
	for letter: String in PairTags.LETTERS:
		var shape: Array = PairTags._letter(letter)
		var positions: PackedVector3Array = shape[0]
		var triangles: PackedInt32Array = shape[1]
		var covered := 0
		var low := INF
		var high := -INF
		var wide := 0.0
		for row in range(GRID):
			for column in range(GRID):
				var at := Vector2((float(column) + 0.5) / GRID - 0.5, (float(row) + 0.5) / GRID - 0.5) * face - Vector2(0, PairTags.FACE_UP)
				for corner in range(0, triangles.size(), 3):
					var a := Vector2(positions[triangles[corner]].x, positions[triangles[corner]].z)
					var b := Vector2(positions[triangles[corner + 1]].x, positions[triangles[corner + 1]].z)
					var c := Vector2(positions[triangles[corner + 2]].x, positions[triangles[corner + 2]].z)
					if Geometry2D.point_is_inside_triangle(at, a, b, c):
						covered += 1
						low = minf(low, at.y + PairTags.FACE_UP)
						high = maxf(high, at.y + PairTags.FACE_UP)
						wide = maxf(wide, absf(at.x))
						break
		var share := float(covered) / float(GRID * GRID)
		var tall := (high - low) / face
		_check(share >= 0.025 and tall >= 0.52 and tall <= 0.64, "The letter %s stands about %.0f%% of its face tall: %.0f%% tall, %.0f%% of the face" % [letter, PairTags.LETTER_SHARE * 100.0, tall * 100.0, share * 100.0])
		_check(maxf(absf(low), absf(high)) <= face * 0.42, "The letter %s keeps a margin inside the face" % letter)
		_check(wide <= face * 0.5 - PairTags.BAND * 2.0, "The letter %s leaves room for a band at each edge of the face" % letter)
	for style: String in Styles.SLOTS.tag:
		_check(PairTags.FRAMES.has(StringName(str(Styles.SLOTS.tag[style].frame))), "The tag style %s has a frame" % style)

## The pop-up's chip reads at phone size: CHIP canvas pixels on a 1280 by 720
## canvas that a 2400 by 1080 phone draws half again as big, its letter's caps
## LETTER_SHARE of the face; the font's capital measures as a capital; the near
## and lit faces stay apart and the ink letter reads on both.
func _chip_size() -> void:
	const PHONE := 1080.0 / 720.0
	var letter := PairTags.CHIP / PairTags.TAG * PairTags.LETTER_HEIGHT * PHONE
	_check(PairTags.CHIP * PHONE >= 70.0 and letter >= 28.0, "The pop-up chip is %.0f px on a phone with a %.0f px letter" % [PairTags.CHIP * PHONE, letter])
	_check(PairTags._cap_share() > 0.55 and PairTags._cap_share() < 0.8, "A capital is %.2f of the font size" % PairTags._cap_share())
	for colour: Color in PairTags.PALETTE:
		var near := PairTags.chip_face(colour, false)
		var lit := PairTags.chip_face(colour, true)
		_check(_delta(near, lit) >= NEAR_TO_LIT * 0.6, "A lit chip stands off a near one: %s (%.1f)" % [colour.to_html(false), _delta(near, lit)])
		_check(_delta(PairTags.INK, near) >= LETTER_ON_FACE and _delta(PairTags.INK, lit) >= LETTER_ON_FACE, "The chip's letter reads on a near and a lit face: %s" % colour.to_html(false))

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
	_check(pairs.all(func(pair: Dictionary) -> bool: return pair.group == "levers" and pair.prompted), "A lever's letter is in the action pop-up")
	var kinds := PairTags.pairs_of({"bridges": [{"id": "r"}], "pressure_pads": [{"id": "p", "position_cm": [0, 0]}], "ball_pads": [{"id": "b", "position_cm": [0, 0]}], "controls": [{"id": "s", "position_cm": [0, 0]}], "optical_field": {"receivers": [{"id": "e", "position_cm": [0, 0]}]}, "gates": [{"route_id": "r", "pad_id": "p", "ball_pad_id": "b", "when": {"all": [{"control_id": "s", "value": "x"}, {"signal_id": "e"}]}}]})
	var read := kinds.map(func(pair: Dictionary) -> Array: return [pair.control, pair.group, pair.prompted])
	_check(read == [["p", "pressure_pads", true], ["b", "ball_pads", false], ["s", "controls", true], ["e", "receivers", false]], "Pads and selectors are named in the pop-up; ball pads and receivers keep a floor tile: %s" % [read])
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
		var beside := tiles.any(func(tile: Dictionary) -> bool: return PairTags.CONTROL in tile.sides)
		if pair.prompted: _check(not beside, "%s: %s (in the action pop-up) has no floor tile" % [where, pair.control])
		else: _check(beside, "%s: %s (no pop-up names it) shows its tile beside it" % [where, pair.control])
		for route: Dictionary in pair.gates:
			_check(tiles.any(func(tile: Dictionary) -> bool: return str(route.id) in tile.gates), "%s: %s shows its tile at the gate of %s" % [where, pair.control, route.id])
		var looks := tiles.map(func(tile: Dictionary) -> String: return "%s%d" % [tile.letter, tile.band])
		# The pop-up names the input with the letter its gates show.
		var chip: Dictionary = tags.badge(pair.control, {})
		_check(not looks.is_empty() and "%s%d" % [chip.get("letter", ""), chip.get("band", -1)] == looks[0] and chip.get("colour") == PairTags.colour_of(pair.index) and chip.get("frame") == tags._frame, "%s: %s's pop-up chip shows its tiles' letter and colour: %s against %s" % [where, pair.control, chip, looks])
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
	var turnable: Array = view.get("controls", []).filter(func(control: Dictionary) -> bool: return str(control.get("kind", "")) == "mirror")
	for pair: Dictionary in wired:
		if pair.group == "receivers" and not turnable.is_empty():
			_check(pair.inputs.all(func(input: Dictionary) -> bool: return input.group == "controls") and not pair.inputs.is_empty(), "%s: the receiver %s has the mirrors that light it as its inputs: %s" % [where, pair.control, pair.inputs.map(func(input: Dictionary) -> String: return input.id)])
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
	var at: Vector3 = world._pair_control_anchor(pair.inputs[0].entity)
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
		var toggles: bool = each.kind != &"other" or each.group == "receivers"
		_check(tags.badge(each.control, alone).lit == toggles and not tags.badge(each.control, far).lit, "%s: %s's pop-up chip lights while it is on (a selector's never: it has no off)" % [where, each.control])
		_per_gate(tags, where, each, far)
	_activate(active, pair)
	# Out of order: the same snapshot gives the same states after any other.
	tags.present(far)
	var before: Dictionary = tags.states()
	tags.present(active)
	tags.present(far)
	_check(tags.states() == before, "%s: a snapshot shows the same states whatever came before" % where)
	_prompts(world, where, wired)

## A selector's tile at a gate glows only at a value that gate asks, even with
## every gate open; a receiver's own tile only while one of its gates is open,
## never for the light alone.
func _per_gate(tags, where: String, pair: Dictionary, far: Dictionary) -> void:
	if pair.kind != &"other": return
	var open := far.duplicate(true)
	for route: Dictionary in pair.gates: open.bridges[str(route.id)] = true
	var asked_any: Array = []
	for route: Dictionary in pair.gates:
		for value: String in pair.values.get(str(route.id), []):
			if value not in asked_any: asked_any.append(value)
	for value: String in asked_any:
		var at_value := open.duplicate(true)
		at_value["controls"] = {pair.control: value}
		tags.present(at_value)
		for tile: Dictionary in tags.tile_states():
			if tile.control != pair.control or (tile.gates as Array).is_empty(): continue
			var wanted: bool = (tile.gates as Array).any(func(route: String) -> bool: return pair.values.get(route, []).is_empty() or value in pair.values.get(route, []))
			_check(tile.lit == wanted, "%s: at %s, %s's tile at %s %s" % [where, value, pair.control, tile.gates, "glows" if wanted else "stays unlit"])
	if pair.group == "receivers":
		var light := far.duplicate(true)
		light["optics"] = {"signals": {pair.control: true}}
		tags.present(light)
		_check(not tags.states()[pair.control].lit, "%s: the receiver %s does not glow for the light alone, only with its gate open" % [where, pair.control])
		if pair.inputs.any(func(input: Dictionary) -> bool: return input.group == "controls"):
			_check(tags.badge(pair.control, light).lit and not tags.badge(pair.control, far).lit, "%s: the mirrors' chip for %s lights while the light reaches it" % [where, pair.control])
	tags.present(far)

## The pop-up's chip for the live pip: the input its action names, a pad of
## its own it stands at, nothing when far or at an input with no pair; the
## other pip's pop-up never names a pad it does not hold; the same snapshot
## gives the same chip after any other.
func _prompts(world: Node3D, where: String, wired: Array[Dictionary]) -> void:
	var tags = world.pair_tags
	for pair: Dictionary in wired:
		for input: Dictionary in pair.inputs:
			if input.group not in PairTags.PROMPTED: continue
			var slot := str(input.entity.get("owner_slot", "p0"))
			var at: Vector3 = world._pair_control_anchor(input.entity)
			var far := {"active_slot": slot, "players": {"p0": {"x": 99999, "z": 99999, "height": 0}, "p1": {"x": -99999, "z": -99999, "height": 0}}, "levers": {}, "hold_pads": {}, "bridges": {}}
			var near := far.duplicate(true)
			near.players[slot] = {"x": at.x * 100.0, "z": at.z * 100.0, "height": at.y * 100.0}
			if input.group != "pressure_pads": near["context_action"] = {"id": "lever", "label": "Pull lever", "enabled": true, "target_id": input.id}
			_check(tags.prompt(far).is_empty(), "%s: no chip while the live pip is far from every input" % where)
			var chip: Dictionary = tags.prompt(near)
			# A mirror lighting two receivers names the first pair it works.
			var owner: Dictionary = wired.filter(func(each: Dictionary) -> bool: return each.inputs.any(func(other: Dictionary) -> bool: return other.id == input.id))[0]
			_check(chip.get("control", "") == owner.control and chip.get("input", "") == input.id and chip.get("letter", "") == PairTags.letter_of(owner.index), "%s: the pop-up at %s names %s: %s" % [where, input.id, owner.control, chip])
			if input.group == "pressure_pads":
				var other := near.duplicate(true)
				other.active_slot = "p1" if slot == "p0" else "p0"
				other.players[other.active_slot] = near.players[slot]
				_check(tags.prompt(other).get("input", "") != input.id, "%s: the other pip's pop-up never names %s, a pad it does not hold" % [where, input.id])
			if owner != pair: continue
			var lit := near.duplicate(true)
			_activate(lit, pair)
			var on: Dictionary = tags.prompt(lit)
			var toggles: bool = pair.kind != &"other" or pair.group == "receivers"
			_check(tags.prompt(near) == chip and not bool(chip.get("lit", true)) and bool(on.get("lit", false)) == toggles, "%s: %s's chip at %s follows the snapshot alone, lit while on (a selector's never)" % [where, pair.control, input.id])
			if input.group == "pressure_pads":
				var bell := near.duplicate(true)
				bell["context_action"] = {"id": "ring", "label": "Ring bell", "enabled": true, "target_id": "goal"}
				_check(tags.prompt(bell).is_empty(), "%s: on %s with another button up, that button carries no pad letter" % [where, input.id])
	var nothing := {"active_slot": "p0", "players": {}, "context_action": {"label": "Ring bell", "target_id": "no-such-control"}}
	_check(tags.prompt(nothing).is_empty(), "%s: an action at an input with no pair shows no chip" % where)

## Makes `pair` active in `state` the way its kind is read.
static func _activate(state: Dictionary, pair: Dictionary) -> void:
	match pair.kind:
		&"lever": state.levers[pair.control] = true
		&"pad": state.hold_pads[pair.control] = true
		_:
			if pair.group == "receivers": state["optics"] = {"signals": {pair.control: true}}
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
		for input: Dictionary in pair.inputs:
			var at: Vector3 = world._pair_control_anchor(input.entity)
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
