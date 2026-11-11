extends "res://tests/test_dressing_lint.gd"
## Prop slots, styles and themes (content/dressing/prop_styles.gd, themes.gd,
## catalog.gd resolve()):
##  - every published dressing comes back from the catalog exactly as written,
##  - every style is a kit prop and every theme picks a real style for every slot,
##  - each theme gives back the published chapter it was taken from exactly,
##    with that chapter's props written as slots wherever the theme's picks fit,
##  - High and Low written by hand with slots resolves to its published file,
##  - and each of the prop-mix board's mixes passes the scenery lint on every
##    stage, so a pick never puts a prop on a route or in the camera's way.
const Canonical = preload("res://core/v2/canonical.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Themes = preload("res://content/dressing/themes.gd")
const Samples = preload("res://tests/dressing_mix_samples.gd")
## Kinds drawn for a style whose built props must stay inside their kit
## extent: the lint judges a prop by its extent, so one that grew past it
## could hide a pip unseen.
const BUILT_WITHIN := ["stone_wall", "shells"]
## The largest size a level lays a trim row at, on a bank's front lip this
## high (metres): every trim style stays under Props.LOW there.
const TRIM_SIZE := 0.6
const TRIM_LIP := 0.06
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
				spec["size"] = TRIM_SIZE
				_check(float(Props.extent(spec).height) + TRIM_LIP <= Props.LOW, "Trim style %s stays low enough never to hide a spirit" % style)
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
		_check(field == "picks" or published.has(field), "Theme %s gives only fields its source has (%s)" % [theme, field])
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
