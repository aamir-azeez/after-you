extends "res://tests/test_dressing_lint.gd"
## Prop slots, styles and themes (content/dressing/prop_styles.gd, themes.gd,
## catalog.gd resolve()):
##  - every published dressing comes back from the catalog exactly as written,
##  - every style is a kit prop and every theme picks a real style for every slot,
##  - each theme gives back the published chapter it was taken from exactly,
##    with that chapter's props written as slots wherever the theme's picks fit,
##  - High and Low written by hand with slots resolves to its published file,
##  - each of the prop-mix board's mixes passes the scenery lint on every
##    stage, so a pick never puts a prop on a route or in the camera's way,
##  - props placed by a floor's edge (content/dressing/placement.gd) are cut
##    around crossings and controls by the lint's own rules and stand on the
##    top of their bank,
##  - and no kit prop flickers: each one, at every size a level uses and
##    turned any way, standing on a bank's top, has no z-fighting faces.
const Canonical = preload("res://core/v2/canonical.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Themes = preload("res://content/dressing/themes.gd")
const Samples = preload("res://tests/dressing_mix_samples.gd")
## Kit kinds swept for z-fighting at these sizes and turns (degrees) on a bank.
## Shells are left out: a scatter of 2 cm pieces whose layout follows where it
## lies, so the lint judges each cluster where a level lays it.
const SWEPT_KINDS := ["tree", "pine", "bush", "flowers", "rock", "lantern", "lamp_post", "bench", "pot", "fern", "crate", "cottage", "tower", "basket", "boat", "bollard", "barrel", "lobster_pot", "shelf", "frame", "tuft", "signpost", "waterfall", "mill_wheel", "post_box", "reeds", "stamp_desk"]
const SWEPT_SIZES := [0.5, 0.6, 0.8, 1.0, 1.2, 2.0]
const SWEPT_TURNS := [0, 45, 90, 180]

## A stand-in world for the face sweep: the lint reads its terrain.
class Holder extends Node3D:
	var terrain: Node3D
## Kinds drawn for a style whose built props must stay inside their kit
## extent: the lint judges a prop by its extent, so one that grew past it
## could hide a pip unseen.
const BUILT_WITHIN := ["stone_wall", "shells"]
## theme -> [published key it was taken from, least share of its props written as slots]
const SOURCES := {
	"garden": ["high-and-low@1", 0.85],
	"harbour": ["turn-of-the-tide@1", 0.5],
	"house": ["a-house-for-two@1", 0.4],
}

func _run() -> void:
	_check_published()
	_check_styles()
	_check_themes_reproduce()
	_check_hand_written()
	_check_mixes_lint()
	_check_resolve_rules()
	_check_placement()
	_check_kit_faces()
	print("DRESSING MIXES: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_published() -> void:
	for key: String in Catalog.keys():
		var written: Dictionary = Catalog.FILES[key].DATA
		_check(Catalog.problems(written).is_empty(), "Dressing %s resolves cleanly: %s" % [key, Catalog.problems(written)])
		if not Catalog.mixes(written):
			_check(is_same(Catalog.for_key(key), written), "A dressing with no slots comes back exactly as written: " + key)

func _check_styles() -> void:
	for slot: String in Styles.SLOTS:
		_check(Styles.DEFAULT_PICKS.has(slot) and Styles.has_style(slot, str(Styles.DEFAULT_PICKS.get(slot, ""))), "Slot %s has a default style" % slot)
		if slot in Styles.LOOK_SLOTS: continue
		for style: String in Styles.SLOTS[slot]:
			var spec: Dictionary = Styles.style(slot, style).duplicate()
			_check(not spec.has("slot") and spec.has("kind"), "Style %s/%s names a kit kind" % [slot, style])
			var line := str(spec.kind) in Styles.LINE_KINDS
			if line:
				spec["from"] = [0, 0]
				spec["to"] = [100, 0]
			elif spec.kind == "bank": spec["rect"] = [0, 0, 100, 40]
			else: spec["at"] = [0, 0]
			_check(_known(spec), "Style %s/%s builds a kit prop" % [slot, style])
			if str(spec.kind) in BUILT_WITHIN:
				var built := _built_bounds(spec)
				var extent := Props.extent(spec)
				var rect: Rect2 = extent.rect
				_check(built.end.y <= float(extent.base) + float(extent.height) + 0.002 and rect.grow(0.01).encloses(Rect2(built.position.x, built.position.z, built.size.x, built.size.z)), "Style %s/%s stays inside the extent the lint checks (%s, %s)" % [slot, style, built, extent])
			if slot == "trim":
				spec["size"] = PropRules.TRIM_SIZE
				_check(float(Props.extent(spec).height) + PropRules.TRIM_LIP <= Props.LOW, "Trim style %s stays low enough never to hide a spirit" % style)
	for slot: String in Styles.DEFAULT_PICKS: _check(Styles.SLOTS.has(slot), "Default pick names a slot: " + slot)
	for theme: String in Themes.THEMES:
		var picks: Dictionary = Themes.THEMES[theme].get("picks", {})
		for slot: String in Styles.SLOTS: _check(Styles.has_style(slot, str(picks.get(slot, ""))), "Theme %s picks a style for %s" % [theme, slot])
		_check(picks.keys().all(func(slot: String) -> bool: return Styles.SLOTS.has(slot)), "Theme %s picks only real slots" % theme)

## Each theme's published source, its props written as slots wherever a pick
## fits, resolves back to the published file byte for byte.
func _check_themes_reproduce() -> void:
	for theme: String in SOURCES:
		var key: String = SOURCES[theme][0]
		var published: Dictionary = Catalog.FILES[key].DATA
		var written := _as_slots(published, theme)
		var resolved := Catalog.resolve(written.data)
		_check(Catalog.problems(written.data).is_empty(), "Theme %s rewrite of %s has no problems" % [theme, key])
		_check(JSON.stringify(Canonical.normalized(resolved)) == JSON.stringify(Canonical.normalized(published)), "Theme %s gives back %s exactly" % [theme, key])
		var share := float(written.slotted) / float(maxi(1, written.total))
		print("THEME %s from %s: %d of %d props as slots (%.0f%%)" % [theme, key, written.slotted, written.total, share * 100.0])
		_check(share >= float(SOURCES[theme][1]), "Theme %s fits most of %s's props (%d of %d)" % [theme, key, written.slotted, written.total])

func _check_hand_written() -> void:
	var published: Dictionary = Catalog.FILES[Samples.KEY].DATA
	_check(Catalog.problems(Samples.HIGH_AND_LOW).is_empty(), "The hand-written slot dressing has no problems")
	_check(JSON.stringify(Canonical.normalized(Catalog.resolve(Samples.HIGH_AND_LOW))) == JSON.stringify(Canonical.normalized(published)), "High and Low written with slots resolves to its published dressing")

func _check_mixes_lint() -> void:
	var mixes := Samples.mixes()
	for name: String in mixes:
		_check(Catalog.problems(mixes[name]).is_empty(), "Mix %s has no problems: %s" % [name, Catalog.problems(mixes[name])])
		var resolved := Catalog.resolve(mixes[name])
		var before := failures
		for stage_id: String in _stage_ids(Samples.KEY):
			_lint(Samples.KEY, stage_id, _stage_view(Samples.KEY, stage_id), resolved)
		_check(failures == before, "Mix %s passes the scenery lint on every stage" % name)
	var harbour := Catalog.resolve(mixes.harbour)
	_check(harbour.look == "dusk" and harbour.ground == {"*": "terracotta", "loft": "timber"} and harbour.fireflies == 12, "A theme fills the level's fields and the level's ground wins island by island")
	var kinds: Array = Props.expand(Catalog.stage_props(harbour, Samples.STAGE)).map(func(spec: Dictionary) -> String: return str(spec.kind))
	_check("lamp_post" in kinds and "lantern" not in kinds and "wall" in kinds and "stone_wall" in kinds, "The harbour mix stands its own lamps, stone walls and railing")
	_check(kinds.count("shells") == 3, "Shells lay half the clusters their line asks for, its ends kept (%d of 6)" % kinds.count("shells"))
	var mixed := Catalog.resolve(mixes.garden_mixed)
	var mixed_kinds: Array = Props.expand(Catalog.stage_props(mixed, Samples.STAGE)).map(func(spec: Dictionary) -> String: return str(spec.kind))
	_check("pine" in mixed_kinds and "tree" not in mixed_kinds and mixed.look == "golden" and mixed.stairs == "timber", "A level overrides its theme slot by slot")

func _check_resolve_rules() -> void:
	var picks := {"theme": "garden", "picks": {"lamp": "lamp_post"}, "props": {"*": [
		{"slot": "lamp", "at": [0, 0], "size": 0.8},
		{"slot": "lamp", "style": "lantern", "at": [100, 0]},
		{"slot": "lamp", "from": [0, 0], "to": [300, 0], "count": 3, "y": 4},
		{"kind": "row", "of": {"slot": "trim", "size": 0.5}, "from": [0, 0], "to": [100, 0]},
	]}}
	var made: Array = Catalog.resolve(picks).props["*"]
	_check(made[0] == {"kind": "lamp_post", "at": [0, 0], "size": 0.8}, "A slot prop takes the level's pick and keeps its own fields")
	_check(made[1].kind == "lantern", "A prop's own style beats the pick")
	_check(made[2] == {"kind": "row", "of": {"kind": "lamp_post"}, "from": [0, 0], "to": [300, 0], "count": 3, "y": 4}, "A point style along a line is a row")
	_check(made[3].of == {"kind": "flowers", "size": 0.5}, "A row's slot prop resolves inside it")
	var shells: Array = Catalog.resolve({"props": {"*": [{"kind": "row", "of": {"slot": "scatter", "style": "shells"}, "from": [0, 0], "to": [500, 0], "count": 6},
		{"slot": "scatter", "style": "shells", "from": [0, 0], "to": [500, 0], "count": 6}]}}).props["*"]
	_check(shells.all(func(row: Dictionary) -> bool: return row.count == 3 and not row.of.has("row_every")), "A thinned style lays half its line either way it is written: %s" % [shells])
	var broken := {"props": {"*": [{"slot": "lamp", "style": "torch", "at": [0, 0]}, {"slot": "fence", "at": [0, 0]}, {"slot": "nothing", "at": [0, 0]}]}}
	_check(Catalog.resolve(broken).props["*"].is_empty() and Catalog.problems(broken).size() == 3, "Unknown styles, slots and a line style without a line are left out and named")
	_check(not Catalog.problems({"theme": "castle"}).is_empty(), "An unknown theme is named")

## Placing by a floor's edge on a small made-up stage: one floor with a
## crossing off its front and a lever by its front edge.
func _check_placement() -> void:
	var view := {
		"islands": [{"id": "lawn", "rect_cm": [0, 0, 600, 400], "height_cm": 0}],
		"bridges": [{"id": "jetty", "rect_cm": [250, 400, 350, 600], "height_cm": 0}],
		"controls": [{"id": "lever", "position_cm": [500, 370], "radius_cm": 30, "surface_id": "lawn"}],
	}
	var bank := {"kind": "bank", "slot": "bank", "floor": "lawn", "edge": "front", "depth": 50, "height": 6}
	var trim := {"kind": "flowers", "slot": "trim", "floor": "lawn", "edge": "front", "spacing": 60}
	var lamp := {"kind": "lantern", "slot": "lamp", "floor": "lawn", "edge": "back", "along": 0.5}
	var back := {"kind": "bank", "slot": "bank", "floor": "lawn", "edge": "back", "depth": 80, "height": 12}
	var laid := Placement.lay([], [bank, trim, lamp, back], view)
	var banks: Array = laid.filter(func(spec: Dictionary) -> bool: return spec.kind == "bank" and spec.rect[1] == 400)
	var cut := PropRules.MARGIN * 100.0
	var clear := (0.3 + PropRules.CLEAR) * 100.0
	_check(banks.size() == 3 and banks[0].rect[2] <= 250 - cut + 1 and banks[1].rect[0] >= 350 + cut - 1 and banks[1].rect[2] <= 500 - clear + 1 and banks[2].rect[0] >= 500 + clear - 1, "A front bank is cut around the crossing and the lever, the lint's margins clear: %s" % [banks])
	_check(banks.all(func(spec: Dictionary) -> bool: return spec.rect[3] == 450 and not spec.has("floor") and not spec.has("depth")), "A placed bank lies outside its edge as deep as asked and passes on no placing field")
	var flowers: Array = laid.filter(func(spec: Dictionary) -> bool: return spec.kind == "flowers")
	var stage := PropRules.scene(view)
	_check(not flowers.is_empty() and flowers.all(func(spec: Dictionary) -> bool: return float(spec.y) == Props.bank_top(banks[0]) and float(spec.size) <= PropRules.TRIM_SIZE and PropRules.faults(spec, stage).is_empty()), "Front trim stands on its bank's top at trim size, off the crossing and the lever: %s" % [flowers])
	_check(flowers.all(func(spec: Dictionary) -> bool: return absf(float(spec.at[0]) - 500.0) > 30.0 + PropRules.CLEAR * 100.0), "No trim stands over the lever")
	var lanterns: Array = laid.filter(func(spec: Dictionary) -> bool: return spec.kind == "lantern")
	_check(lanterns.size() == 1 and lanterns[0].at == [300, -40] and float(lanterns[0].y) == 13.5, "A prop on a back bank stands at its middle on its top: %s" % [lanterns])
	var tall := Placement.lay([], [bank, {"kind": "tree", "slot": "tree", "floor": "lawn", "edge": "front", "spacing": 100}], view)
	_check(tall.all(func(spec: Dictionary) -> bool: return spec.kind != "tree" or PropRules.low(PropRules.footing(spec, stage.heights))), "Anything on a front edge is laid low enough never to hide a pip")
	var hand := Placement.lay([{"kind": "pot", "at": [300, -40], "surface": "lawn"}, {"kind": "pot", "at": [300, 200], "surface": "lawn"}], [back], view)
	_check(float(hand[0].get("y", 0)) == 13.5 and not hand[1].has("y"), "A hand-placed prop with no height stands on the bank under it, and only there")
	var data := {"theme": "garden", "edged": {"*": ["front", "sideways"]}, "props": {"*": [{"slot": "lamp", "floor": "lawn", "edge": "front", "at": [0, 0]}]}}
	_check(Catalog.problems(data).size() == 2, "An unknown edge and a placed prop with its own spot are named: %s" % [Catalog.problems(data)])
	_check(Catalog.resolve(data).get("props", {}).is_empty(), "Without the chapter's key nothing is placed")
	var grown := Placement.grown({"lawn": ["front"]}, Themes.THEMES.garden.edging, view)
	_check(grown.size() == Themes.THEMES.garden.edging.front.size() and grown.all(func(spec: Dictionary) -> bool: return spec.floor == "lawn" and spec.edge == "front"), "A theme grows its front edging along the named floor")
	for key: String in Catalog.keys():
		if not Placement.used(Catalog.FILES[key].DATA): continue
		var resolved := Catalog.for_key(key)
		var stages := Placement.stage_ids(key)
		_check(resolved.props.keys().all(func(stage: String) -> bool: return stage == "*" or stage in stages), "A placed dressing lists its props under * or a stage: " + key)
		_check(stages.all(func(stage_id: String) -> bool: return not Catalog.stage_props(resolved, stage_id).is_empty()), "A placed dressing places props on every stage: " + key)

## Every kit prop at every swept size and turn, standing on a bank's top, has
## no z-fighting faces, with the bank or itself (test_dressing_lint's sweep).
func _check_kit_faces() -> void:
	var bank := {"kind": "bank", "rect": [-150, -150, 150, 150], "height": 12}
	for kind: String in SWEPT_KINDS:
		var bad: Array = []
		for size: float in SWEPT_SIZES:
			for turn: int in SWEPT_TURNS:
				var holder := Holder.new()
				holder.terrain = Node3D.new()
				holder.add_child(holder.terrain)
				root.add_child(holder)
				Props.build(bank, holder.terrain, 0.0, true)
				Props.build({"kind": kind, "at": [0, 0], "y": Props.bank_top(bank), "size": size, "rot": turn}, holder.terrain, 0.0, true)
				var found := coplanar_pairs(holder, null, COPLANAR)
				if not found.is_empty(): bad.append("size %s turned %d: %s" % [size, turn, found[0]])
				holder.free()
		_check(bad.is_empty(), "Kit %s never flickers on a bank at any size or turn: %s" % [kind, bad.slice(0, 3)])

## The world box of every vertex one prop draws, built at the origin.
func _built_bounds(spec: Dictionary) -> AABB:
	var holder := Node3D.new()
	root.add_child(holder)
	Props.build(spec, holder, 0.0, true)
	var bounds := AABB()
	var first := true
	# Every drawn vertex, not each mesh's box: a turned box overstates a pebble.
	for mesh: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		for vertex: Vector3 in mesh.mesh.get_faces():
			var point: Vector3 = mesh.global_transform * vertex
			if first: bounds = AABB(point, Vector3.ZERO)
			else: bounds = bounds.expand(point)
			first = false
	holder.free()
	return bounds

## {data, slotted, total}: the published dressing under `theme`, each prop
## whose fields hold one of the theme's picked styles written as that slot.
func _as_slots(published: Dictionary, theme: String) -> Dictionary:
	var preset: Dictionary = Themes.THEMES[theme]
	var data: Dictionary = {"theme": theme}
	for field: String in published:
		if field == "props": continue
		var given: Variant = preset.get(field)
		if field == "ground" and given is Dictionary:
			var ground: Dictionary = {}
			for island: String in published.ground:
				if given.get(island) != published.ground[island]: ground[island] = published.ground[island]
			if not ground.is_empty(): data["ground"] = ground
		elif given != published[field]: data[field] = published[field]
	for field: String in preset:
		_check(field in Catalog.MIX_FIELDS or published.has(field), "Theme %s gives only fields its source has (%s)" % [theme, field])
	var slotted := 0
	var total := 0
	var props: Dictionary = {}
	for stage: String in published.get("props", {}):
		var specs: Array = []
		for spec: Dictionary in published.props[stage]:
			total += 1
			var written := _slot_spec(spec, preset.picks)
			if written.has("slot"): slotted += 1
			specs.append(written)
		props[stage] = specs
	data["props"] = props
	return {"data": data, "slotted": slotted, "total": total}

## The spec as a slot prop when a picked style's fields are all in it.
func _slot_spec(spec: Dictionary, picks: Dictionary) -> Dictionary:
	var row := str(spec.get("kind", "")) == "row"
	var inner: Dictionary = spec.of if row else spec
	if row and not spec.keys().all(func(field: String) -> bool: return field in ["kind", "of"] or field in Styles.ROW_FIELDS): return spec
	for slot: String in Styles.SLOTS:
		if slot in Styles.LOOK_SLOTS: continue
		var style := Styles.style(slot, str(picks.get(slot, "")))
		if style.is_empty() or not style.keys().all(func(field: String) -> bool: return inner.has(field) and inner[field] == style[field]): continue
		var line := str(style.kind) in Styles.LINE_KINDS
		if line and not row and not (spec.has("from") and spec.has("to")): continue
		var written := {"slot": slot}
		for field: String in inner:
			if not style.has(field): written[field] = inner[field]
		if row:
			if line: continue
			for field: String in spec:
				if field in Styles.ROW_FIELDS: written[field] = spec[field]
		return written
	return spec
