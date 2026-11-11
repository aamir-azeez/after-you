extends SceneTree
## The level checker, from the definitions and the dressing alone (no world):
## every stage of every chapter laid out as floors and crossings, published or
## not (superseded versions included), and a failure names the chapter, the
## stage and the spot.
##  - Reach (tests/level_graph.gd): a floor no stage lets either pip reach;
##    on a stage, a control, lever or pad its owner cannot reach and stand
##    on, and a ring goal its pip cannot reach. The graph over-approximates
##    (a gate counts as open once anything reachable could make it hold), so
##    each failure here is a spot no real play reaches.
##  - Props (content/dressing, kit/props.gd extents): two props standing in
##    each other on a stage. Props against routes, pads, levers, goals and
##    starts, and the camera's view of them, are tests/test_dressing_lint.gd's.
##    Scenery a world builds in code is not dressing and is not covered here.
## The bubbles and the camera's framing need a built world:
## tests/test_level_view.gd. KNOWN lists what fails on purpose, with why; an
## entry that stops failing fails the suite, so the list never goes stale.
const Registry = preload("res://services/chapter_registry.gd")
const Families = preload("res://services/chapter_families.gd")
const Index = preload("res://content/chapters/index.gd")
const LevelGraph = preload("res://tests/level_graph.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Dressing = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
## Two props stand in each other when their footprints share more than this
## much of the smaller one's (and their heights meet): touching leaves and a
## lamp beside a crate are fine, one crate inside another is not.
const PROP_SHARE := 0.3
## Known failures: {failure id: why it is left}. Published worlds never change
## to clear one; a new chapter fixes its own.
const KNOWN := {}
var checks := 0
var failures := 0
var _found: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var covered := 0
	var skipped: Array[String] = []
	for key: String in Registry.keys():
		if not Stages.floor_chapter(key):
			skipped.append(key)
			_check(Stages.NOT_FLOOR_FAMILIES.has(str(Index.data(key).family)), "%s: a chapter with no floors to check names its family in NOT_FLOOR_FAMILIES" % key)
			continue
		var started := Time.get_ticks_msec()
		_reach(key)
		_props(key)
		covered += 1
		print("LEVEL CHECKER: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	_check(covered >= 8, "The checker walks every floor chapter (%d)" % covered)
	for family: String in Stages.NOT_FLOOR_FAMILIES:
		_check(Families.row(family).get("cooperative", true) == false, "%s is listed as having no floors, and is no floor family" % family)
	for id: String in KNOWN:
		_check(_found.has(id), "Known failure still fails, or comes off the list: %s (%s)" % [id, KNOWN[id]])
	print("LEVEL CHECKER: %d chapters, skipped %s" % [covered, skipped])
	print("LEVEL CHECKER: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

## A spot that must hold: it fails unless KNOWN lists its id.
func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		_found[id] = true
		if KNOWN.has(id):
			print("KNOWN: %s (%s)" % [message, KNOWN[id]])
			ok = true
	_check(ok, message)

# --- Reach ----------------------------------------------------------------------

func _reach(key: String) -> void:
	var level := Registry.definition(key)
	var graph: RefCounted = LevelGraph.new(level)
	var journey := Registry.is_journey(key)
	var seen: Dictionary = {}
	for item: Dictionary in Stages.stages(key, level):
		var stage: Dictionary = item.view
		var where := "%s %s" % [key, stage.stage_id]
		if item.checkpoint.is_empty():
			_check(false, "%s: no checkpoint to open from (write the chapter's fixtures)" % where)
			continue
		var found: Dictionary = graph.reach(stage, item.checkpoint, journey)
		for slot: String in found.floors:
			for id: String in found.floors[slot]: seen[id] = true
		for kind: String in ["controls", "levers", "pressure_pads"]:
			for entity: Dictionary in stage.get(kind, []):
				_stand(graph, found, entity, where, kind)
		var goal: Dictionary = stage.get("goal", {})
		if not goal.is_empty():
			if str(stage.get("goal_policy", {}).get("kind", "ring")) == "ring":
				_stand(graph, found, goal, where, "goal")
			else:
				var surface := str(goal.get("surface_id", ""))
				_expect(found.floors.p0.has(surface) or found.floors.p1.has(surface), "%s goal %s" % [where, goal.id], "%s: neither pip reaches the goal %s's floor %s at %s" % [where, goal.id, surface, _cm(goal.position_cm)])
	for island: Dictionary in level.islands:
		_expect(seen.has(str(island.id)), "%s floor %s" % [key, island.id], "%s: no stage lets either pip reach the floor %s (%s)" % [key, island.id, _rect(island.rect_cm)])

## The entity's owner reaches its floor and can stand within its radius.
func _stand(graph: RefCounted, found: Dictionary, entity: Dictionary, where: String, kind: String) -> void:
	var slot := str(entity.get("owner_slot", ""))
	var surface := str(entity.get("surface_id", ""))
	var label := "%s %s" % [_kind_name(kind), entity.id]
	var id := "%s %s" % [where, label]
	if slot.is_empty():
		var either: bool = found.floors.p0.has(surface) or found.floors.p1.has(surface)
		_expect(either, id, "%s: neither pip reaches the %s on %s at %s" % [where, label, surface, _cm(entity.position_cm)])
		return
	var reached: bool = found.floors.get(slot, {}).has(surface)
	_expect(reached, id, "%s: %s never reaches the %s on %s at %s" % [where, slot, label, surface, _cm(entity.position_cm)])
	if reached: _expect(graph.can_stand_at(entity, slot, found.open), id + " stand", "%s: %s cannot stand within reach of the %s at %s on %s" % [where, slot, label, _cm(entity.position_cm), surface])

static func _kind_name(kind: String) -> String:
	match kind:
		"controls": return "selector"
		"levers": return "lever"
		"pressure_pads": return "pad"
	return kind

# --- Props ----------------------------------------------------------------------

func _props(key: String) -> void:
	var data := Dressing.for_key(key)
	if data.get("props", {}).is_empty(): return
	var level := Registry.definition(key)
	var heights: Dictionary = {}
	for island: Dictionary in level.islands: heights[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	for stage: Dictionary in level.stages:
		var where := "%s %s" % [key, stage.id]
		var solid: Array = []
		for spec: Dictionary in Props.expand(Dressing.stage_props(data, str(stage.id))):
			var extent := Props.extent(spec)
			if bool(extent.flat) or str(spec.get("kind", "")) == "bank": continue
			var base := float(heights.get(str(spec.get("surface", "")), 0.0)) + float(extent.base)
			solid.append({"spec": spec, "rect": extent.rect, "round": _round(spec), "low": base, "high": base + float(extent.height)})
		for a in range(solid.size()):
			for b in range(a + 1, solid.size()):
				var one: Dictionary = solid[a]
				var two: Dictionary = solid[b]
				if one.high <= two.low + 0.01 or two.high <= one.low + 0.01: continue
				var share := _share(one, two)
				var id := "%s props %s and %s" % [where, _prop(one.spec), _prop(two.spec)]
				_expect(share <= PROP_SHARE, id, "%s: the %s and the %s stand in each other (%d%% of the smaller)" % [where, _prop(one.spec), _prop(two.spec), roundi(share * 100.0)])

## Round kinds keep a circle footprint; boxes and lines keep their rectangle.
static func _round(spec: Dictionary) -> bool:
	return str(spec.get("kind", "")) not in ["bench", "cottage", "rug", "path", "planter", "boat", "lobster_pot", "shelf", "frame", "fence", "hedge", "wall"]

## How much of the smaller footprint the two share, from 0 to 1 (a circle is
## sampled on a 9 by 9 grid over its square).
static func _share(one: Dictionary, two: Dictionary) -> float:
	var small: Dictionary = one if _area(one) <= _area(two) else two
	var large: Dictionary = two if small == one else one
	if not (small.rect as Rect2).intersects(large.rect): return 0.0
	var inside := 0
	var total := 0
	var rect: Rect2 = small.rect
	for i in range(9):
		for j in range(9):
			var point := rect.position + rect.size * Vector2((float(i) + 0.5) / 9.0, (float(j) + 0.5) / 9.0)
			if not _covers(small, point): continue
			total += 1
			if _covers(large, point): inside += 1
	return float(inside) / float(maxi(total, 1))

static func _covers(item: Dictionary, point: Vector2) -> bool:
	var rect: Rect2 = item.rect
	if not item.round: return rect.has_point(point)
	return point.distance_to(rect.get_center()) <= rect.size.x * 0.5

static func _area(item: Dictionary) -> float:
	var rect: Rect2 = item.rect
	return rect.get_area() * (PI / 4.0 if item.round else 1.0)

static func _prop(spec: Dictionary) -> String:
	return "%s at %s" % [spec.get("kind", "?"), _cm(spec.get("at", spec.get("from", [0, 0])))]

static func _cm(at: Array) -> String:
	return "(%d, %d) cm" % [int(at[0]), int(at[1])]

static func _rect(r: Array) -> String:
	return "(%d, %d) to (%d, %d) cm" % [int(r[0]), int(r[1]), int(r[2]), int(r[3])]
