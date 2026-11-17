extends SceneTree
## The quick prop check: in seconds, every stage of one chapter's dressing
## judged by the dressing lint's own rules (presentation/kit/prop_rules.gd and
## the lint's face sweep, tests/test_dressing_lint.gd), not a copy of them:
##  - where props may stand: ground a tall prop may take, and ground only a
##    low one may (in front, where a tall one would hide a pip),
##  - each prop on a walking space, over a control or start, hiding one from
##    the camera, or standing in another prop,
##  - and faces of the dressing that would flicker (z-fight), as built.
## Headless: --key=<chapter key> [--stages=a,b] [--no-faces]. Prints one line
## per finding, then PROP CHECK with the total; exits 1 when there is any. The
## map plan draws the same result (map_plan.gd, map_plan_view.gd).
const Catalog = preload("res://content/dressing/catalog.gd")
const Placement = preload("res://content/dressing/placement.gd")
const Props = preload("res://presentation/kit/props.gd")
const PropRules = preload("res://presentation/kit/prop_rules.gd")
const ChapterIndex = preload("res://content/chapters/index.gd")
const Lint = preload("res://tests/test_dressing_lint.gd")
const Kit = preload("res://tests/level_tools/render_kit.gd")
## The probes for where props may stand: a lamp post for anything tall, low
## trim for the rest.
const TALL := {"kind": "lamp_post"}
const LOW := {"kind": "flowers", "size": 0.6}
## How far past the floors (cm) the stand map reaches, and its finest cell.
const REACH := 160.0
const CELL := 20.0
## The stand map stays under about this many cells, so it takes a second.
const MOST_CELLS := 6000

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var options := Kit.args()
	var key := str(options.get("key", ""))
	if key.is_empty() or key not in Catalog.keys():
		print("NOTE give --key=<a dressed chapter key>: %s" % [Catalog.keys()])
		quit(2)
		return
	var started := Time.get_ticks_msec()
	var stages: Array = Placement.stage_ids(key)
	if options.has("stages"): stages = stages.filter(func(id: String) -> bool: return id in str(options.stages).split(","))
	var total := 0
	for stage_id: String in stages:
		var result := check(key, stage_id)
		for line: String in lines(result): print("%s %s: %s" % [key, stage_id, line])
		total += lines(result).size()
	if not options.has("no-faces"):
		for line: String in faces(root, key, stages):
			print(line)
			total += 1
	print("PROP CHECK %s: %d findings in %d ms" % [key, total, Time.get_ticks_msec() - started])
	quit(1 if total > 0 else 0)

## One stage's props judged ({} data: the chapter's own dressing):
## {"props": [{spec, rect (cm), faults: ["walkable island x", ...]}],
##  "stand": {"tall": [Rect2 cm], "low": [Rect2 cm]}}.
static func check(key: String, stage_id: String, data: Dictionary = {}) -> Dictionary:
	var dressing := data if not data.is_empty() else Catalog.for_key(key)
	var view := Placement.stage_view(key, stage_id)
	var descriptor: Dictionary = {} if key == Lint.LIGHTHOUSE else ChapterIndex.data(key)
	var stage := PropRules.scene(view, PropRules.sized_levers(view, descriptor, dressing))
	var props: Array = []
	var solids: Array = []
	for spec: Dictionary in Props.expand(Catalog.stage_props(dressing, stage_id)):
		var found: Array = PropRules.faults(spec, stage).map(func(fault: Dictionary) -> String: return "%s %s" % [fault.rule, fault.target])
		var solid := PropRules.solid(spec, stage.heights)
		for index in range(solids.size()):
			if PropRules.clash(solid, solids[index]): found.append("stands in the %s" % _name(props[index].spec))
		solids.append(solid)
		var area: Rect2 = Props.extent(spec).rect
		props.append({"spec": spec, "rect": Rect2(area.position * 100.0, area.size * 100.0), "faults": found})
	return {"props": props, "stand": stand(view, stage)}

## The findings of check() as lines, one per prop that breaks a rule.
static func lines(result: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for prop: Dictionary in result.props:
		if not prop.faults.is_empty(): found.append("%s: %s" % [_name(prop.spec), ", ".join(prop.faults)])
	return found

static func _name(spec: Dictionary) -> String:
	var at: Array = spec.get("at", spec.get("from", spec.get("rect", [0, 0])))
	return "%s at (%d, %d)" % [spec.get("kind", "?"), int(at[0]), int(at[1])]

## Where props may stand on this stage, as cm cells: "tall" where a lamp post
## breaks no rule, "low" where only low trim does. Each cell stands on the
## floor whose edge is nearest.
static func stand(view: Dictionary, stage: Dictionary = {}) -> Dictionary:
	if stage.is_empty(): stage = PropRules.scene(view)
	var floors: Array = view.get("islands", [])
	var bounds := Rect2()
	for island: Dictionary in floors:
		var area := PropRules.rect(island.rect_cm)
		bounds = area if not bounds.has_area() else bounds.merge(area)
	bounds = Rect2(bounds.position * 100.0, bounds.size * 100.0).grow(REACH)
	var cell := maxf(CELL, ceilf(sqrt(bounds.get_area() / float(MOST_CELLS)) / 5.0) * 5.0)
	var result := {"tall": [], "low": []}
	var z := bounds.position.y
	while z < bounds.end.y:
		var x := bounds.position.x
		while x < bounds.end.x:
			var centre := Vector2(x, z) + Vector2.ONE * cell * 0.5
			var surface := _nearest(floors, centre)
			var at := [roundi(centre.x), roundi(centre.y)]
			if PropRules.faults(TALL.merged({"at": at, "surface": surface}), stage).is_empty(): result.tall.append(Rect2(x, z, cell, cell))
			elif PropRules.faults(LOW.merged({"at": at, "surface": surface}), stage).is_empty(): result.low.append(Rect2(x, z, cell, cell))
			x += cell
		z += cell
	return result

static func _nearest(floors: Array, point: Vector2) -> String:
	var best := ""
	var reach := INF
	for island: Dictionary in floors:
		var r: Array = island.rect_cm
		var distance := Vector2(maxf(maxf(float(r[0]) - point.x, point.x - float(r[2])), 0.0), maxf(maxf(float(r[1]) - point.y, point.y - float(r[3])), 0.0)).length()
		if distance < reach:
			reach = distance
			best = str(island.id)
	return best

## Faces of the dressing that z-fight, with each other or anything else, on
## each stage as built (the lint's own face and pip shadow sweeps).
static func faces(parent: Node, key: String, stages: Array) -> Array[String]:
	var found: Array[String] = []
	var world := Lint.dressed_world(parent, key)
	for stage_id: String in stages:
		Lint.show_dressed_stage(world, key, stage_id)
		var gap := Lint.min_gap(world)
		var pairs := Lint.coplanar_pairs(world, null, gap)
		pairs.append_array(Lint.shadow_pairs(world, Placement.stage_view(key, stage_id), gap))
		for pair: String in pairs:
			if not pair.contains("Prop_"): continue
			var line := "%s %s: flickers: %s" % [key, stage_id, pair]
			if line not in found: found.append(line)
	world.free()
	return found
