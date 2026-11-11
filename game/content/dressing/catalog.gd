extends RefCounted
## Scenery as data. One dressing file per chapter key, kept apart from the
## hashed chapter definitions: nothing here reaches a simulation, a recording
## or a checkpoint. A chapter without a file keeps its world exactly as built.
##
## A dressing file declares `const DATA := {...}` with optional fields:
##   "look":   kit/look.gd preset name
##   "ground": {island_id or "*": kit/surfaces.gd style}
##   "stairs": "timber" for wooden steps, "bridges": "timber" for plank decks
##   "obstacles": "flowerbed" for timber flower beds on obstacle rectangles
##   "cables": "floor" to draw gate links only along a shared floor
##   "props":  {"*" or stage_id: [kit/props.gd specs]}; a "lamp_post" may
##             name "bunting": [x, z], where a light pool under it and bunting
##             strung from it end (tide_world)
##   "decks":  {route id: deck kind} for a world that builds its own decks
##             (tide_world: sand, stones, jetty, gangway, towpath, punt)
##   "moored_boats": [{"at": [x, z], "heading": radians, "water": body id}]:
##             rowboats riding a body of water (kit/water_bodies.gd)
##   "fireflies": count of drifting lights near the props (dusk looks)
##   "theme":  a content/dressing/themes.gd preset filling every field above
##             the file leaves out ("ground" island by island)
##   "picks":  {slot: style}, over the theme's (content/dressing/prop_styles.gd)
## A prop may name a "slot" instead of a "kind"; resolve() turns it into the
## picked style's kind here, once per key, so every reader (the worlds, the
## lint) sees plain kit specs. A file with no theme, picks or slot props is
## returned exactly as written.
## tests/test_dressing_lint.gd checks every prop against every route, pad,
## lever, goal, start and drop, including the camera's view of them.

const Index = preload("res://content/chapters/index.gd")
const Styles = preload("res://content/dressing/prop_styles.gd")
const Themes = preload("res://content/dressing/themes.gd")
## Dressing for keys that are not registered chapters. A registered chapter
## names its file in its descriptor ("dressing").
const OTHER_FILES := {
	"sleeping-lighthouse@1": preload("res://content/dressing/sleeping_lighthouse.gd"),
}
## Fields a theme does not pass on as they are.
const MIX_FIELDS := ["theme", "picks", "props"]
## Key -> dressing script, loaded once with this file, then only read.
static var FILES: Dictionary = _files()
## Key -> resolved dressing data, worked out once with this file, then only read.
static var RESOLVED: Dictionary = _resolve_files()

static func _files() -> Dictionary:
	var result: Dictionary = OTHER_FILES.duplicate()
	for key: String in Index.keys():
		var path: String = Index.data(key).dressing
		if not path.is_empty(): result[key] = load(path)
	result.make_read_only()
	return result

static func _resolve_files() -> Dictionary:
	var result: Dictionary = {}
	for key: String in FILES:
		var data: Dictionary = resolve(FILES[key].DATA)
		# A mixed dressing is new data: locked like the const files it stands for.
		if not data.is_read_only(): data.make_read_only()
		result[key] = data
	result.make_read_only()
	return result

static func for_key(key: String) -> Dictionary:
	return RESOLVED.get(key, {})

static func keys() -> Array:
	return FILES.keys()

## Every prop spec shown on one stage, rows expanded by the caller.
static func stage_props(data: Dictionary, stage_id: String) -> Array:
	var props: Dictionary = data.get("props", {})
	return props.get("*", []) + props.get(stage_id, [])

## The dressing with its theme and picks applied and every slot prop turned
## into its style's kit spec. Returns `data` itself when it mixes nothing. A
## slot, style or theme that does not exist is left out (problems() names it).
static func resolve(data: Dictionary) -> Dictionary:
	if not mixes(data): return data
	var theme: Dictionary = Themes.THEMES.get(str(data.get("theme", "")), {})
	var result: Dictionary = {}
	for field: String in theme:
		if field not in MIX_FIELDS: result[field] = theme[field].duplicate() if theme[field] is Dictionary else theme[field]
	for field: String in data:
		if field in MIX_FIELDS: continue
		if field == "ground" and result.get("ground") is Dictionary: result.ground.merge(data.ground, true)
		else: result[field] = data[field]
	var picks: Dictionary = Styles.DEFAULT_PICKS.duplicate()
	picks.merge(theme.get("picks", {}), true)
	picks.merge(data.get("picks", {}), true)
	var props: Dictionary = {}
	for stage: String in data.get("props", {}):
		var specs: Array = []
		for spec: Dictionary in data.props[stage]:
			var made := _resolve_spec(spec, picks)
			if not made.is_empty(): specs.append(made)
		props[stage] = specs
	if data.has("props"): result["props"] = props
	return result

## True when the dressing names a theme, picks or any slot prop.
static func mixes(data: Dictionary) -> bool:
	if data.has("theme") or data.has("picks"): return true
	for stage: String in data.get("props", {}):
		for spec: Dictionary in data.props[stage]:
			if spec.has("slot") or (spec.get("of") is Dictionary and spec.of.has("slot")): return true
	return false

## What resolve() had to leave out, as messages; empty when nothing.
static func problems(data: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var theme := str(data.get("theme", ""))
	if data.has("theme") and not Themes.THEMES.has(theme): found.append("Unknown theme " + theme)
	var picks: Dictionary = Styles.DEFAULT_PICKS.duplicate()
	picks.merge(Themes.THEMES.get(theme, {}).get("picks", {}), true)
	for slot: String in data.get("picks", {}):
		if not Styles.has_style(slot, str(data.picks[slot])): found.append("Unknown pick %s: %s" % [slot, data.picks[slot]])
	picks.merge(data.get("picks", {}), true)
	for stage: String in data.get("props", {}):
		for spec: Dictionary in data.props[stage]:
			var inner: Dictionary = spec.of if spec.get("of") is Dictionary else spec
			if not inner.has("slot"): continue
			if inner.has("kind"): found.append("A slot prop names a kind too: %s" % inner)
			var name := str(inner.get("style", picks.get(str(inner.slot), "")))
			if not Styles.has_style(str(inner.slot), name): found.append("No style %s for slot %s" % [name, inner.slot])
			elif _resolve_spec(spec, picks).is_empty(): found.append("A %s line needs from and to: %s" % [inner.slot, spec])
	return found

static func _resolve_spec(spec: Dictionary, picks: Dictionary) -> Dictionary:
	if spec.get("of") is Dictionary and spec.of.has("slot"):
		var row: Dictionary = spec.duplicate()
		row.of = _styled(spec.of, picks)
		return {} if row.of.is_empty() else row
	if not spec.has("slot"): return spec
	var styled := _styled(spec, picks)
	if styled.is_empty(): return {}
	var line := spec.has("from") and spec.has("to")
	var line_kind := str(styled.kind) in Styles.LINE_KINDS
	if line_kind and not line: return {}
	if line_kind or not line: return styled
	# A point style laid along a line: a kit row of it.
	var row := {"kind": "row", "of": {}}
	for field: String in styled:
		if field in Styles.ROW_FIELDS: row[field] = styled[field]
		else: row.of[field] = styled[field]
	return row

## The style's fields under the spec's own; {} for an unknown slot or style.
static func _styled(spec: Dictionary, picks: Dictionary) -> Dictionary:
	var slot := str(spec.slot)
	var style := Styles.style(slot, str(spec.get("style", picks.get(slot, ""))))
	if style.is_empty() or spec.has("kind"): return {}
	var result: Dictionary = style.duplicate(true)
	for field: String in spec:
		if field != "slot" and field != "style": result[field] = spec[field]
	return result
