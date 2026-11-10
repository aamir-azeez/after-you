extends SceneTree
## Ownership marks (presentation/kit/owner_mark.gd), built in every stage of
## every chapter whose world marks owners:
## - every owned lever, control, pad, stair, crossing and zone gets its marks
##   in its owner's slot: one for a control, pad or stair, two for a crossing
##   (one past each end) unless its world shows the owner some other way, one
##   per step along a zone, one for a source's waiting region and for the goal
##   cradle of a world that marks it; every mark names an owned thing of its slot;
## - each mark lies within the stage's floors, a crossing's end marks on its
##   deck's height, clear of every other mark and off every other crossing's deck;
## - every diamond and ring on the stage came from the kit (a hand-drawn mark
##   fails here), and once the world's static fold has run none is left as a
##   draw call of its own: marks share their colour's batch.
## Marks are presentation only; the stage definition is never changed.
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const OwnerMark = preload("res://presentation/kit/owner_mark.gd")
const LevelHints = preload("res://presentation/kit/level_hints.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const StaticBatch = preload("res://presentation/kit/static_batch.gd")
const Canonical = preload("res://core/v2/canonical.gd")
## Kinds that mark one thing once.
const SINGLE := [&"lever", &"mirror", &"stair", &"ladder", &"pad", &"bucket", &"spot"]
## Goals whose world marks their cradle, by level id: the tide's harbour
## lantern and every Long Way Home window ("*").
const MARKED_GOALS := {"turn-of-the-tide": ["harbour-lantern"], "long-way-home": ["*"]}
## How far outside its floors a mark may lie (a stair's foot mark, a crossing's end).
const FLOOR_MARGIN := 0.3
## Marks closer than this in height share a floor.
const SAME_FLOOR := 0.05
## The ring's reach: Primitives.ring_mesh's outer radius.
const RING_REACH := OwnerMark.RING_RADIUS + 0.025
## Marks drawn as they were on main when the kit came in (changing them is a
## visible change, which waits for the owner): "<chapter key>: <check> <kind>
## <id>" -> why, for every stage of that chapter. An entry that no failing
## check matches fails, so the list shrinks as each is settled.
const UNOWNED_TIDE_STAIRS := ["w-steps-low", "w-steps-high", "rock-steps-low", "rock-steps-high", "mole-steps", "mole-slip", "mill-steps", "east-steps"]
const UNOWNED_STAIR := "a stair nobody owns wears the second spirit's ring: cooperative_world marks every stair (for the owner)"
const KNOWN := {
	"turn-of-the-tide@1: deck lever sluice": "the sluice's mark reaches onto the top tread of the boathouse steps in front of it",
	"turn-of-the-tide@2: deck lever sluice": "the sluice's mark reaches onto the top tread of the boathouse steps in front of it",
	"the-wishing-well@1: apart ladder well-ladder": "the rope ladder's mark and the resting bucket's lie 17 cm apart",
	"the-wishing-well@1: apart route_end rope-walk-west": "the two rope walks' facing end marks lie 12 cm apart",
	"the-wishing-well@1: fold bucket": "the bucket's mark rides the moving bucket: one draw call",
	"conservatory@1: fold mirror": "conservatory_world keeps everything a mirror build adds (_remember_fixtures), its mark too: one draw call each",
}
var checks := 0
var failures := 0
var _known := {}
var _known_seen := {}

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	_known = KNOWN.duplicate()
	for key: String in ["turn-of-the-tide@1", "turn-of-the-tide@2"]:
		for id: String in UNOWNED_TIDE_STAIRS: _known["%s: owner stair %s" % [key, id]] = UNOWNED_STAIR
	_table()
	var marked := 0
	for key: String in Registry.keys():
		var world: Node3D = Registry.world_script(key).new()
		if not "owner_marks" in world:
			world.free()
			continue
		root.add_child(world)
		world.set_process(false)
		var level := Registry.definition(key)
		var digest := Canonical.digest(level)
		world.load_level(level)
		for stage: Dictionary in level.stages:
			world.show_stage(stage)
			_check(world.displayed_stage_id == stage.id, "%s builds %s" % [key, stage.id])
			marked += _stage(world, key, CooperativeCatalog.stage_definition(level, str(stage.id)))
		_check(Canonical.digest(level) == digest, "%s: marks never change the definition" % key)
		world.free()
	_check(marked > 100, "The sweep sees the chapters' marks: %d" % marked)
	for id: String in _known: _check(_known_seen.has(id), "KNOWN names '%s', which no check fails now: delete it" % id)
	print("OWNER MARKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The kit's table.
func _table() -> void:
	for kind: StringName in OwnerMark.KINDS:
		var spec: Dictionary = OwnerMark.KINDS[kind]
		_check(spec.has("reach") and spec.has("lift") and float(spec.reach) >= 0.0 and float(spec.lift) >= 0.0, "KINDS %s says how far and how high" % kind)
	_check(is_equal_approx(OwnerMark.REACH, OwnerMark.SIDE * 0.7072), "A diamond reaches its side times 0.7072")
	var ends := OwnerMark.route_end_points([100, -50, 300, 50])
	_check(ends[0].is_equal_approx(Vector3(0.82, 0, 0)) and ends[1].is_equal_approx(Vector3(3.18, 0, 0)), "A crossing's end marks lie its reach past each end: %s" % [ends])
	# The floor-cable tag's top lies midway between the crossing mark's top and the cable's.
	var tag_top := LevelHints.LINK_LIFT + LevelHints.LINK_TAG_THICKNESS * 0.5
	_check(is_equal_approx(tag_top - (OwnerMark.ROUTE_LIFT + OwnerMark.THICKNESS * 0.5), LevelHints.LINK_LIFT + LevelHints.LINK_WIDTH * 0.5 - tag_top), "A link tag's top sits midway between the mark's and the cable's")
	for style: StringName in LevelHints.STYLES:
		var spec: Dictionary = LevelHints.STYLES[style]
		_check(spec.bar is Vector3 and float(spec.spacing) > (spec.bar as Vector3).x, "Hint style %s keeps its bars apart" % style)

## One stage's checks; returns how many marks it has.
func _stage(world: Node3D, key: String, view: Dictionary) -> int:
	var where := "%s %s" % [key, world.displayed_stage_id]
	var placed: Array[Dictionary] = world.owner_marks.placed()
	var owners := _owned(view)
	var by_id: Dictionary = {}
	for mark: Dictionary in placed:
		var id := str(mark.id)
		if not by_id.has(id): by_id[id] = []
		by_id[id].append(mark)
		if mark.kind == &"handoff":
			_check(view.has("handoff"), "%s: a handoff mark on a stage with a handoff" % where)
			continue
		_known_or_check(key, where, "owner %s %s" % [mark.kind, id], owners.has(id), "names something owned on this stage")
		if owners.has(id): _check(owners[id].slot == mark.slot, "%s: %s is marked %s, its owner's slot (%s)" % [where, id, mark.slot, owners[id].slot])
	for id: String in owners:
		var owned: Dictionary = owners[id]
		var marks: Array = by_id.get(id, [])
		match owned.what:
			"route":
				var expected := 2 if world._marks_route_owner(owned.entity) else 0
				_check(marks.size() == expected and marks.all(func(m: Dictionary) -> bool: return m.kind == &"route_end"), "%s: crossing %s has %d end marks (%d)" % [where, id, expected, marks.size()])
			"zone":
				var r: Array = owned.entity.rect_cm
				var expected := range(int(r[0]) + OwnerMark.ZONE_FIRST_CM, int(r[2]), OwnerMark.ZONE_STEP_CM).size()
				_check(marks.size() == expected, "%s: zone %s has a mark every %d cm (%d of %d)" % [where, id, OwnerMark.ZONE_STEP_CM, marks.size(), expected])
			"goal":
				var marked: Array = MARKED_GOALS.get(key.get_slice("@", 0), [])
				var expected := 1 if "*" in marked or id in marked else 0
				_check(marks.size() == expected and marks.all(func(m: Dictionary) -> bool: return m.kind == &"goal"), "%s: the goal %s has %d marks (%d)" % [where, id, expected, marks.size()])
			"endpoint":
				_check(marks.size() == 1 and marks[0].kind == &"endpoint", "%s: the source's waiting region %s has one mark (%d)" % [where, id, marks.size()])
			_:
				_check(marks.size() == 1 and SINGLE.has(marks[0].kind), "%s: %s %s has exactly one mark (%d)" % [where, owned.what, id, marks.size()])
	if view.has("handoff"):
		var slots: Array = by_id.get("handoff", []).map(func(m: Dictionary) -> String: return str(m.slot))
		slots.sort()
		_check(slots == ["p0", "p1"], "%s: the handoff has one mark per spirit" % where)
	_placement(key, where, view, placed, owners)
	_drawn(world, key, where, placed)
	return placed.size()

## Owned things of the stage: id -> {slot, what, entity}.
func _owned(view: Dictionary) -> Dictionary:
	var found: Dictionary = {}
	for pair: Array in [["levers", "control"], ["controls", "control"], ["pressure_pads", "pad"], ["stairs", "stair"], ["bridges", "route"], ["access_zones", "zone"]]:
		for entity: Dictionary in view.get(pair[0], []):
			if str(entity.get("owner_slot", "")).is_empty(): continue
			found[str(entity.get("id", ""))] = {"slot": str(entity.owner_slot), "what": pair[1], "entity": entity}
	var goal: Dictionary = view.get("goal", {})
	if not str(goal.get("owner_slot", "")).is_empty(): found[str(goal.get("id", "goal"))] = {"slot": str(goal.owner_slot), "what": "goal", "entity": goal}
	var endpoint: Dictionary = view.get("source_policy", {}).get("endpoint", {})
	if not endpoint.is_empty(): found[str(endpoint.get("id", "endpoint"))] = {"slot": str(endpoint.owner_slot), "what": "endpoint", "entity": endpoint}
	return found

## Within the floors, a crossing's ends on its height, apart, off other decks.
func _placement(key: String, where: String, view: Dictionary, placed: Array[Dictionary], owners: Dictionary) -> void:
	var floors: Array = []
	for island: Dictionary in view.get("islands", []): floors.append([_rect(island.rect_cm), float(island.get("height_cm", 0)) / 100.0, "island", str(island.id)])
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []):
		floors.append([_rect(route.rect_cm), float(route.get("height_cm", route.get("from_height_cm", 0))) / 100.0, "deck", str(route.id)])
	for index in range(placed.size()):
		var mark: Dictionary = placed[index]
		if mark.kind == &"spot": continue
		var at: Vector3 = mark.at
		var flat := Vector2(at.x, at.z)
		var reach := _reach(str(mark.slot))
		var tag := "%s %s" % [mark.kind, mark.id]
		var inside := false
		for entry: Array in floors:
			if (entry[0] as Rect2).grow(FLOOR_MARGIN).has_point(flat): inside = true
		_known_or_check(key, where, "floors " + tag, inside, "lies within the stage's floors at %s" % flat)
		var owned: Dictionary = owners.get(str(mark.id), {})
		if mark.kind == &"route_end" and not owned.is_empty():
			var deck := float(owned.entity.get("height_cm", 0)) / 100.0
			_known_or_check(key, where, "height " + tag, is_equal_approx(at.y - OwnerMark.ROUTE_LIFT, deck), "lies on its crossing's height %.2f (%.3f)" % [deck, at.y])
		var stands_on := str(owned.get("entity", {}).get("surface_id", ""))
		for entry: Array in floors:
			# A mark may lie on the deck its own machine stands on, and a stair's on its stair.
			if entry[2] != "deck" or entry[3] == stands_on or entry[3] == str(mark.id) or absf(at.y - float(entry[1])) >= 0.1: continue
			var footprint := Rect2(flat - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)
			_known_or_check(key, where, "deck " + tag, not (entry[0] as Rect2).intersects(footprint), "lies off the deck of %s" % entry[3])
		for other in range(index + 1, placed.size()):
			var them: Dictionary = placed[other]
			if them.kind == &"spot" or absf((them.at as Vector3).y - at.y) > SAME_FLOOR: continue
			var apart := flat.distance_to(Vector2((them.at as Vector3).x, (them.at as Vector3).z))
			_known_or_check(key, where, "apart " + tag, apart >= reach + _reach(str(them.slot)), "lies clear of %s mark %s (%.3f m)" % [them.kind, them.id, apart])

## Every diamond and ring of the stage is one of the kit's marks, and the
## static fold leaves none drawing on its own.
func _drawn(world: Node3D, key: String, where: String, placed: Array[Dictionary]) -> void:
	var drawn := _mark_nodes(world)
	var expected := placed.filter(func(mark: Dictionary) -> bool: return mark.kind != &"spot")
	_check(drawn.size() == expected.size(), "%s: every mark on the stage came from the kit (%d drawn, %d placed)" % [where, drawn.size(), expected.size()])
	_check(placed.filter(func(mark: Dictionary) -> bool: return mark.kind == &"spot").size() == world._stand_spots.size(), "%s: each stand spot's mark is recorded" % where)
	StaticBatch.fold(world.terrain, [world], world._fold_options())
	for node: MeshInstance3D in _mark_nodes(world):
		# By where it stands across the floor: a bucket may have risen since.
		var at: Vector3 = world.terrain.to_local(node.global_position)
		var mark: Dictionary = {}
		for candidate: Dictionary in expected:
			if Vector2((candidate.at as Vector3).x, (candidate.at as Vector3).z).is_equal_approx(Vector2(at.x, at.z)): mark = candidate
		_known_or_check(key, where, "fold %s %s" % [mark.get("kind", "?"), mark.get("id", node.name)], false, "folds into its colour's batch")

## The kit's diamonds and rings standing as their own nodes under the terrain.
func _mark_nodes(world: Node3D) -> Array:
	var diamond := Primitives.cached_box(Vector3(OwnerMark.SIDE, OwnerMark.THICKNESS, OwnerMark.SIDE))
	var ring := Primitives.cached_shape(Primitives.ring_mesh(OwnerMark.RING_RADIUS))
	var gold := Primitives.shared_material(OwnerMark.GOLD)
	var teal := Primitives.shared_material(OwnerMark.TEAL)
	return world.terrain.find_children("*", "MeshInstance3D", true, false).filter(func(node: MeshInstance3D) -> bool: return (node.mesh == diamond and node.material_override == gold) or (node.mesh == ring and node.material_override == teal))

func _reach(slot: String) -> float:
	return OwnerMark.REACH if slot == "p0" else RING_REACH

static func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

## A check that may fail as KNOWN says: `what` is "<check> <kind> <id>".
func _known_or_check(key: String, where: String, what: String, ok: bool, detail: String) -> void:
	var id := "%s: %s" % [key, what]
	if not ok:
		for known: String in _known:
			# An entry names one mark ("<check> <kind> <id>") or every mark of a kind.
			if id == known or id.begins_with(known + " "):
				_known_seen[known] = true
				return
	_check(ok, "%s: %s %s" % [where, what, detail])

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
